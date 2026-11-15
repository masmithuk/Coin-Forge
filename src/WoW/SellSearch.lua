-- SellSearch: live prices from auction house searches.
--
-- Two jobs:
--   * When you pick an item to sell, search it. A full scan can be up to 15
--     minutes old; a live search is current and also says which listings are
--     yours, so we never undercut ourselves.
--   * Listen to every search, including ones you make in Blizzard's Buy tab, and
--     hand complete results to `onListings` so the price data stays current.
--
-- Results can arrive a page at a time. Our own search pages through to the end
-- before anything is used. Other searches are only recorded once complete:
-- paging them ourselves would spend the AH's request limit.
local _, ns = ...

local SellSearch = {}
SellSearch.__index = SellSearch
ns.SellSearch = SellSearch

--- @param onResults function(item, listings) for the item you picked to sell.
--- @param onListings function(itemID, listings) for every complete search (optional).
---   listings are cheapest first: { {price (per unit), count, mine} }
function SellSearch.new(onResults, onListings)
  return setmetatable({ onResults = onResults, onListings = onListings }, SellSearch)
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

local function isComplete(hasFull, key)
  return not hasFull or hasFull(key)
end

function SellSearch:onEvent(event, arg)
  local ah = C_AuctionHouse
  local item = self.pending
  local itemID, listings, ours

  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" and arg then
    itemID = arg
    ours = item and item.isCommodity and item.itemID == itemID
    if not isComplete(ah.HasFullCommoditySearchResults, itemID) then
      if ours and ah.RequestMoreCommoditySearchResults then ah.RequestMoreCommoditySearchResults(itemID) end
      return
    end
    listings = commodityResults(itemID)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and type(arg) == "table" and arg.itemID then
    itemID = arg.itemID
    ours = item and not item.isCommodity and item.itemID == itemID
    if not isComplete(ah.HasFullItemSearchResults, arg) then
      if ours and ah.RequestMoreItemSearchResults then ah.RequestMoreItemSearchResults(arg) end
      return
    end
    listings = itemResults(arg)
  else
    return
  end

  if self.onListings then self.onListings(itemID, listings) end
  if ours then
    self.pending = nil
    self.onResults(item, listings)
  end
end
