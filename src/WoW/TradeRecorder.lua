-- TradeRecorder: logs your AH and vendor trades into History.
--
-- Everything is observed with hooksecurefunc (after the call), so Blizzard's own
-- buttons keep working untainted, and both Coin Forge's Sell tab and the default
-- UI are covered:
--   AH commodity buy  StartCommoditiesPurchase + COMMODITY_PRICE_UPDATED (price)
--                     + ConfirmCommoditiesPurchase, logged on COMMODITY_PURCHASE_SUCCEEDED
--   AH item buy       PlaceBid (quantity from the current search results),
--                     logged on AUCTION_HOUSE_PURCHASE_COMPLETED
--   post              PostCommodity / PostItem, with the Sell tab's suggested price
--                     if it announced one (expectPost) and the deposit
--   sold              the sale mail's invoice (quantity and money), once per mail
--   expired           the "Your auction of X has expired." system message
--   vendor buy        BuyMerchantItem
--   vendor sale       new entries on the merchant's buyback list
-- Buys are tagged with the deal Coin Forge was showing for that item, if any.
local _, ns = ...

local TradeRecorder = {}
TradeRecorder.__index = TradeRecorder
ns.TradeRecorder = TradeRecorder

TradeRecorder.AH_KINDS = { "flip", "vendor", "arbitrage", "disenchant", "conversion", "craft", "craftInstead" }
TradeRecorder.VENDOR_KINDS = { "vendorFlip" }

--- @param deps { book = fn() -> History book of the current market,
---   dealFor = fn(itemID, kinds) -> { kind, profit, qty } or nil }
function TradeRecorder.new(deps)
  return setmetatable({ deps = deps, expected = {}, bids = {}, buyback = {} }, TradeRecorder)
end

local function hook(tbl, name, fn)
  if tbl and type(tbl[name]) == "function" and hooksecurefunc then hooksecurefunc(tbl, name, fn) end
end

function TradeRecorder:install()
  local ah = C_AuctionHouse
  hook(ah, "PostCommodity", function(location, duration, qty, unitPrice)
    self:posted(location, duration, qty, unitPrice, true)
  end)
  hook(ah, "PostItem", function(location, duration, qty, _, buyout)
    self:posted(location, duration, qty, buyout, false)
  end)
  hook(ah, "StartCommoditiesPurchase", function(itemID, qty) self.quote = { itemID = itemID, qty = qty } end)
  hook(ah, "ConfirmCommoditiesPurchase", function(itemID, qty)
    local quote = self.quote
    local unit = quote and quote.itemID == itemID and quote.unit
    self.buying = unit and { itemID = itemID, qty = qty, unit = unit } or nil
  end)
  hook(ah, "PlaceBid", function(auctionID, bid) self.bids[auctionID] = self:auctionBought(auctionID, bid) end)
  hook(_G, "BuyMerchantItem", function(index, qty) self:boughtFromVendor(index, qty) end)
  hook(_G, "BuybackItem", function() self.buyingBack = true end)
end

--- The Sell tab announces the price it suggested just before it posts.
function TradeRecorder:expectPost(itemID, suggested)
  self.expected[itemID] = suggested
end

local function book(self) return self.deps.book() end

function TradeRecorder:buy(itemID, qty, unitPrice, kinds)
  if not (itemID and qty and qty > 0 and unitPrice) then return end
  book(self):buy(itemID, qty, math.floor(unitPrice + 0.5), self.deps.dealFor(itemID, kinds))
end

function TradeRecorder:posted(location, duration, qty, unitPrice, commodity)
  local ok, itemID = pcall(C_Item.GetItemID, location)
  if not ok or not itemID or not unitPrice then return end
  local ah, deposit = C_AuctionHouse, 0
  if commodity and ah.CalculateCommodityDeposit then
    deposit = ah.CalculateCommodityDeposit(itemID, duration, qty) or 0
  elseif not commodity and ah.CalculateItemDeposit then
    local fine, d = pcall(ah.CalculateItemDeposit, location, duration, qty)
    deposit = fine and d or 0
  end
  local suggested = self.expected[itemID]
  self.expected[itemID] = nil
  book(self):post(itemID, qty, unitPrice, suggested, deposit)
end

function TradeRecorder:auctionBought(auctionID, bid)
  local key = self.itemKey
  local qty = 1
  local ah = C_AuctionHouse
  if key and ah.GetNumItemSearchResults and ah.GetItemSearchResultInfo then
    for i = 1, ah.GetNumItemSearchResults(key) or 0 do
      local r = ah.GetItemSearchResultInfo(key, i)
      if r and r.auctionID == auctionID then
        qty = r.quantity or 1
        break
      end
    end
  end
  return { itemID = key and key.itemID, qty = qty, unit = bid / qty }
end

function TradeRecorder:boughtFromVendor(index, qty)
  local itemID = GetMerchantItemID and GetMerchantItemID(index)
  local _, _, price, stack = GetMerchantItemInfo(index)
  if not itemID or not price or price <= 0 then return end
  stack = (stack and stack > 0) and stack or 1
  self:buy(itemID, qty or stack, price / stack, TradeRecorder.VENDOR_KINDS)
end

-- Buyback list --------------------------------------------------------------

local function readBuyback()
  local list = {}
  for i = 1, (GetNumBuybackItems and GetNumBuybackItems()) or 0 do
    local _, _, price, qty = GetBuybackItemInfo(i)
    local id = ns.Api.itemIDFromLink(GetBuybackItemLink(i))
    list[i] = { id = id, qty = qty or 1, price = price or 0,
      key = tostring(id) .. ":" .. tostring(qty) .. ":" .. tostring(price) }
  end
  return list
end

-- Entries added at the end of the list since `old` (the oldest may have dropped
-- off the front when it was full). Nil when the change isn't a plain append.
local function appended(old, new)
  for drop = 0, #old do
    local match = #old - drop <= #new
    for i = 1, #old - drop do
      if not match then break end
      match = old[i + drop].key == new[i].key
    end
    if match then
      local added = {}
      for i = #old - drop + 1, #new do added[#added + 1] = new[i] end
      if drop > 0 and #added ~= drop then return nil end -- a full list drops one per sale
      return added
    end
  end
  return nil
end

function TradeRecorder:merchantUpdated()
  local now = readBuyback()
  if self.buyingBack then
    self.buyingBack = false
  else
    for _, b in ipairs(appended(self.buyback, now) or {}) do
      if b.id and b.qty > 0 then book(self):vendorSale(b.id, b.qty, math.floor(b.price / b.qty + 0.5)) end
    end
  end
  self.buyback = now
end

-- Sales and expiries ----------------------------------------------------------

local function patternOf(format)
  local escaped = format:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
  return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

-- The listed item with this name (only items you've posted can sell or expire).
local function postedItem(self, name)
  for itemID in pairs(book(self):openPostItems()) do
    if ns.ItemInfo.name(itemID) == name then return itemID end
  end
  return nil
end

function TradeRecorder:systemMessage(msg)
  local format = _G.ERR_AUCTION_EXPIRED_S
  if type(msg) ~= "string" or not format then return end
  local name = msg:match(patternOf(format))
  local itemID = name and postedItem(self, name)
  if not itemID then return end
  local b = book(self)
  b:expired(itemID, b:oldestOpenLeft(itemID) or 1)
end

function TradeRecorder:readMail()
  if not (GetInboxNumItems and GetInboxInvoiceInfo) then return end
  local now = time()
  for i = 1, GetInboxNumItems() do
    local kind, itemName, _, bid, _, _, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
    if kind == "seller" and itemName and bid then
      local daysLeft = select(7, GetInboxHeaderInfo(i)) or 0
      local arrived = math.floor((now - (30 - daysLeft) * 86400) / 3600 + 0.5)
      local key = table.concat({ itemName, bid, count or 1, arrived }, "|")
      local itemID = postedItem(self, itemName)
      if itemID and book(self):firstSeenMail(key) then
        book(self):sold(itemID, count or 1, bid - (consignment or 0))
      end
    end
  end
end

-- Events --------------------------------------------------------------------

TradeRecorder.EVENTS = {
  "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
  "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "MERCHANT_SHOW", "MERCHANT_UPDATE", "CHAT_MSG_SYSTEM", "MAIL_INBOX_UPDATE",
}

function TradeRecorder:onEvent(event, ...)
  if event == "COMMODITY_PRICE_UPDATED" then
    if self.quote then self.quote.unit = (...) end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    local b = self.buying
    self.buying = nil
    if b then self:buy(b.itemID, b.qty, b.unit, TradeRecorder.AH_KINDS) end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    self.buying = nil
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    self.itemKey = (...)
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local auctionID = (...)
    local b = self.bids[auctionID]
    self.bids[auctionID] = nil
    if b then self:buy(b.itemID, b.qty, b.unit, TradeRecorder.AH_KINDS) end
  elseif event == "MERCHANT_SHOW" then
    self.buyback = readBuyback()
    self.buyingBack = false
  elseif event == "MERCHANT_UPDATE" then
    self:merchantUpdated()
  elseif event == "CHAT_MSG_SYSTEM" then
    self:systemMessage((...))
  elseif event == "MAIL_INBOX_UPDATE" then
    self:readMail()
  end
end
