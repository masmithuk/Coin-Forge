-- ItemInfo: cached item details in the plain shape Core expects.
-- Returns nil while the client hasn't loaded an item yet; callers just skip it.
local _, ns = ...

local ItemInfo = {}
ns.ItemInfo = ItemInfo

local cache = {}

local function rawInfo(itemID)
  if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(itemID) end
  return GetItemInfo(itemID)
end

--- @return { name, link, quality, itemLevel, classID, sellPrice, texture } or nil
function ItemInfo.get(itemID)
  if not itemID then return nil end
  local cached = cache[itemID]
  if cached then return cached end
  local name, link, quality, itemLevel, _, _, _, _, _, texture, sellPrice, classID = rawInfo(itemID)
  if not name then return nil end
  local info = {
    name = name, link = link, quality = quality, itemLevel = itemLevel,
    classID = classID, sellPrice = sellPrice, texture = texture,
  }
  cache[itemID] = info
  return info
end

function ItemInfo.name(itemID)
  local info = ItemInfo.get(itemID)
  return info and info.name
end
