-- Bags: everything in your bags that can be sold on the auction house.
--
-- Commodities (cloth, herbs, ...) are grouped per item: the AH sells them by
-- unit and pulls from all your stacks. Other items (gear) are grouped per
-- link, because two copies can differ.
local _, ns = ...

local Bags = {}
ns.Bags = Bags

-- Backpack (0), the four bag slots (1-4) and, on retail-based clients like WoW
-- Forever, the reagent bag slot (5) where profession bags such as a skinning
-- bag can go. Missing bags just have no slots.
local FIRST_BAG = 0
local function lastBag()
  return math.max(5, tonumber(_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or 0)
end

local function isCommodity(location)
  local status = C_AuctionHouse.GetItemCommodityStatus and C_AuctionHouse.GetItemCommodityStatus(location)
  return Enum and Enum.ItemCommodityStatus and status == Enum.ItemCommodityStatus.Commodity or false
end

--- @return list of { key, itemID, link, count, postable, isCommodity, bag, slot }
function Bags.sellable()
  if not (C_Container and C_AuctionHouse and _G.ItemLocation) then return {} end
  local byKey, list = {}, {}
  for bag = FIRST_BAG, lastBag() do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isBound then
        local location = _G.ItemLocation:CreateFromBagAndSlot(bag, slot)
        if C_AuctionHouse.IsSellItemValid(location, false) then
          local commodity = isCommodity(location)
          local key = commodity and info.itemID or info.hyperlink
          local entry = byKey[key]
          if entry then
            entry.count = entry.count + (info.stackCount or 1)
          else
            entry = {
              key = key, itemID = info.itemID, link = info.hyperlink, count = info.stackCount or 1,
              isCommodity = commodity, bag = bag, slot = slot,
            }
            -- the server's count covers every stack of a commodity
            entry.postable = C_AuctionHouse.GetAvailablePostCount and C_AuctionHouse.GetAvailablePostCount(location)
            byKey[key] = entry
            list[#list + 1] = entry
          end
        end
      end
    end
  end
  for _, e in ipairs(list) do e.postable = e.postable or e.count end
  return list
end

function Bags.location(item)
  return _G.ItemLocation:CreateFromBagAndSlot(item.bag, item.slot)
end

--- Per bag: how many slots, items and sellable items were found (for /cforge bags).
--- @return list of { bag, slots, items, sellable }
function Bags.diagnose()
  local out = {}
  if not (C_Container and C_AuctionHouse and _G.ItemLocation) then return out end
  for bag = FIRST_BAG, lastBag() do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    local d = { bag = bag, slots = slots, items = 0, sellable = 0 }
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        d.items = d.items + 1
        local location = _G.ItemLocation:CreateFromBagAndSlot(bag, slot)
        if not info.isBound and C_AuctionHouse.IsSellItemValid(location, false) then d.sellable = d.sellable + 1 end
      end
    end
    out[#out + 1] = d
  end
  return out
end
