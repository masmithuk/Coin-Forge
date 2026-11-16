-- ListingStore: a compact saved copy of the last scan's listings, so deals
-- survive a /reload (the server only allows one full scan every 15 minutes).
--
-- Saved form: { marketKey, time, items = { [itemID] = "price:count,price:count" } }
-- Only each item's cheapest MAX_LEVELS price levels are kept; that's all the
-- deal finders look at, and it keeps SavedVariables small.
local _, ns = ...

local ListingStore = {}
ns.ListingStore = ListingStore

ListingStore.MAX_LEVELS = 20

local function encode(list)
  local parts = {}
  for i = 1, math.min(#list, ListingStore.MAX_LEVELS) do
    parts[i] = list[i].price .. ":" .. list[i].count
  end
  return #parts > 0 and table.concat(parts, ",") or nil
end

local function decode(text)
  if type(text) ~= "string" then return nil end
  local list = {}
  for price, count in text:gmatch("(%d+):(%d+)") do
    list[#list + 1] = { price = tonumber(price), count = tonumber(count) }
  end
  return #list > 0 and list or nil
end

--- @param result a scan result { marketKey, listings = {[itemID] = sorted list} }
--- @return the saved form
function ListingStore.save(result, time)
  local items = {}
  for itemID, list in pairs(result.listings) do items[itemID] = encode(list) end
  return { marketKey = result.marketKey, time = time, items = items }
end

--- Replaces (or, with nil, removes) one item in the saved form.
function ListingStore.setItem(saved, itemID, list)
  saved.items[itemID] = list and encode(list) or nil
end

--- @return a scan result { marketKey, time, itemCount, listings } or nil
function ListingStore.load(saved)
  if type(saved) ~= "table" or not saved.marketKey or type(saved.items) ~= "table" then return nil end
  local listings, count = {}, 0
  for itemID, text in pairs(saved.items) do
    local list = decode(text)
    if list then
      listings[itemID] = list
      count = count + 1
    end
  end
  return { marketKey = saved.marketKey, time = saved.time, itemCount = count, listings = listings }
end
