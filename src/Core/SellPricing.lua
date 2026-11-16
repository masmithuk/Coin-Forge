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
--   6. If you can disenchant it and the materials are worth more than both,
--      recommend disenchanting (the posting price is still filled in).
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
---   disenchantValue  net value of disenchanting one, or nil if you can't
---   settings     { undercut, sellFloor, baitShare, minHistoryDays } }
--- @return { action = "post"|"vendor"|"disenchant"|"manual", price, net, reason,
---           competitor, reference, ignored = { qty, count } }
function SellPricing.suggest(input)
  local s = input.settings
  local listings = input.listings
  local trusted = input.value ~= nil and input.historyDays >= s.minHistoryDays
  local reference = trusted and input.value or ns.Stats.weightedPercentile(listings, 0.5) or input.value

  if not reference then
    local result = { action = "manual", reason = "No price data yet. Scan the AH or set a price yourself.",
      ignored = { qty = 0, count = 0 }, listings = {} }
    return SellPricing.compareDisenchant(result, input)
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

  -- A copy of the listings saying what we made of each one, for display.
  local explained = {}
  for i, l in ipairs(listings) do
    local status
    if ignoreCheap and l.price < floor then status = isBait and "bait" or "war"
    elseif l == competitor then status = l.mine and "yours" or "undercut"
    elseif l.mine then status = "yours"
    else status = "above" end
    explained[i] = { price = l.price, count = l.count, mine = l.mine, status = status }
  end
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
    listings = explained, floor = math.floor(floor), trusted = trusted,
  }
  if input.vendorSell and input.vendorSell > 0 and net <= input.vendorSell then
    result.action = "vendor"
    result.reason = ("A vendor pays %s, more than the %s you'd get here after the cut. Sell it to a vendor.")
      :format(ns.Money.short(input.vendorSell), ns.Money.short(net))
  end
  return SellPricing.compareDisenchant(result, input)
end

--- Switches the advice to "disenchant" when the materials are worth more than
--- both posting (after the cut) and vendoring.
function SellPricing.compareDisenchant(result, input)
  local de = input.disenchantValue
  if not de or de <= 0 then return result end
  local postNet = result.net or 0
  local vendor = input.vendorSell or 0
  if de > postNet and de > vendor then
    result.action = "disenchant"
    local alternatives = {}
    if result.net then alternatives[#alternatives + 1] = "posting gets " .. ns.Money.short(postNet) end
    if vendor > 0 then alternatives[#alternatives + 1] = "a vendor pays " .. ns.Money.short(vendor) end
    result.reason = ("Disenchant it: the materials are worth about %s after the cut%s.")
      :format(ns.Money.short(de), #alternatives > 0 and (", while " .. table.concat(alternatives, " and ")) or "")
  end
  return result
end
