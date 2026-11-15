-- SellPricing: picks the price to post an item at, without falling for traps.
--
-- The rules, in order:
--   1. Work out the item's normal price ("reference"): its market value when it
--      has enough history, otherwise the median of what's listed right now.
--   2. Listings far under normal (below reference * sellFloor) are suspicious:
--        * bait  - only a small share of supply (<= baitShare). Someone wants
--                  you to undercut them and crash the price. Always ignored.
--        * price war - a big wall of cheap supply. With trusted history we
--                  refuse to follow it down; without history we can't tell a
--                  real price drop from a trap, so we follow the market.
--   3. Undercut the cheapest remaining competitor by `undercut` copper, unless
--      that listing is yours, in which case match it (never undercut yourself).
--   4. Nobody left to undercut: post at the reference price (or the floor in a
--      price war).
--   5. If what you'd get after the AH cut is no better than a vendor pays,
--      recommend vendoring instead.
local _, ns = ...

local SellPricing = {}
ns.SellPricing = SellPricing

local function totalQty(listings)
  local n = 0
  for _, l in ipairs(listings) do n = n + l.count end
  return n
end

--- @param input {
---   listings     live listings cheapest first: { {price (per unit), count, mine} }
---   value        market value or nil
---   historyDays  days of price history behind `value`
---   vendorSell   what a vendor pays per unit (0 if it can't be vendored)
---   cutRate      AH cut (0.05 / 0.15)
---   settings     { undercut, sellFloor, baitShare, minHistoryDays } }
--- @return { action = "post"|"vendor"|"manual", price, net, reason,
---           competitor, reference, ignored = { qty, count } }
function SellPricing.suggest(input)
  local s = input.settings
  local listings = input.listings
  local trusted = input.value ~= nil and input.historyDays >= s.minHistoryDays
  local reference = trusted and input.value or ns.Stats.weightedPercentile(listings, 0.5) or input.value

  if not reference then
    return { action = "manual", reason = "No price data yet. Scan the AH or set a price yourself.",
      ignored = { qty = 0, count = 0 } }
  end

  local floor = reference * s.sellFloor
  local cheapQty, cheapCount = 0, 0
  for _, l in ipairs(listings) do
    if l.price < floor then cheapQty, cheapCount = cheapQty + l.count, cheapCount + 1 end
  end
  local share = cheapQty > 0 and cheapQty / totalQty(listings) or 0
  local isBait = cheapQty > 0 and share <= s.baitShare
  local isWar = cheapQty > 0 and not isBait and trusted
  local ignoreCheap = isBait or isWar

  local competitor
  for _, l in ipairs(listings) do
    if not (ignoreCheap and l.price < floor) then
      competitor = l
      break
    end
  end

  local price, reason
  if competitor and competitor.mine then
    price = competitor.price
    reason = "Your auction is already the cheapest, so this matches it."
  elseif competitor then
    price = competitor.price - s.undercut
    reason = ("Undercuts the cheapest listing (%s) by %s."):format(
      ns.Money.short(competitor.price), ns.Money.short(s.undercut))
  elseif isWar then
    price = math.floor(floor)
  else
    price = reference
    reason = "No competition, so this is the normal market price."
  end

  local ignored = { qty = ignoreCheap and cheapQty or 0, count = ignoreCheap and cheapCount or 0 }
  if isWar then
    reason = ("Price war: %d cheap units are %d%% under normal. Not following them down; "
      .. "they usually sell out or expire. "):format(cheapQty, math.floor((1 - s.sellFloor) * 100 + 0.5))
      .. (reason or "Posting at the lowest sensible price.")
  elseif isBait then
    reason = ("Ignored %d bait listing%s far under normal. "):format(cheapCount, cheapCount == 1 and "" or "s")
      .. reason
  end

  price = math.max(1, math.floor(price))
  local net = math.floor(price * (1 - input.cutRate))
  local result = {
    action = "post", price = price, net = net, reason = reason, reference = math.floor(reference),
    competitor = competitor and competitor.price or nil, ignored = ignored,
  }
  if input.vendorSell and input.vendorSell > 0 and net <= input.vendorSell then
    result.action = "vendor"
    result.reason = ("A vendor pays %s, more than the %s you'd get here after the cut. Sell it to a vendor.")
      :format(ns.Money.short(input.vendorSell), ns.Money.short(net))
  end
  return result
end
