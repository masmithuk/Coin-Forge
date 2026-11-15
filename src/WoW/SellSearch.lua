-- SellSearch: live prices for one item, fetched when you select it to sell.
--
-- A full scan can be up to 15 minutes old; a live search is current and also
-- tells us which listings are yours, so we never undercut ourselves.
local _, ns = ...

local SellSearch = {}
SellSearch.__index = SellSearch
ns.SellSearch = SellSearch

--- @param onResults function(item, listings) listings cheapest first:
---   { {price (per unit), count, mine} }
function SellSearch.new(onResults)
  return setmetatable({ onResults = onResults }, SellSearch)
end

local function sorts()
  local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
  return { { sortOrder = order, reverseSort = false } }
end

function SellSearch:request(item)
  self.pending = item
  local ah = C_AuctionHouse
  if item.isCommodity then
    if ah.SendSearchQuery then ah.SendSearchQuery(ah.MakeItemKey(item.itemID), sorts(), true) end
  elseif ah.SendSellSearchQuery and ah.GetItemKeyFromItem then
    ah.SendSellSearchQuery(ah.GetItemKeyFromItem(ns.Bags.location(item)), sorts(), true)
  elseif ah.SendSearchQuery then
    ah.SendSearchQuery(ah.MakeItemKey(item.itemID), sorts(), true)
  end
end

local function sortByPrice(list)
  table.sort(list, function(a, b) return a.price < b.price end)
  return list
end

local function commodityResults(itemID)
  local list = {}
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0 do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if r and r.unitPrice then
      list[#list + 1] = { price = r.unitPrice, count = r.quantity or 1, mine = r.containsOwnerItem == true }
    end
  end
  return sortByPrice(list)
end

local function itemResults(itemKey)
  local list = {}
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0 do
    local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount then -- bid-only auctions aren't a buyout price to compete with
      list[#list + 1] = { price = r.buyoutAmount, count = r.quantity or 1, mine = r.containsOwnerItem == true }
    end
  end
  return sortByPrice(list)
end

function SellSearch:onEvent(event, arg)
  local item = self.pending
  if not item then return end
  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" and item.isCommodity and arg == item.itemID then
    self.pending = nil
    self.onResults(item, commodityResults(arg))
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and not item.isCommodity
    and type(arg) == "table" and arg.itemID == item.itemID then
    self.pending = nil
    self.onResults(item, itemResults(arg))
  end
end
