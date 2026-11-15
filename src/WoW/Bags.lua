-- Bags: everything in your bags that can be sold on the auction house.
--
-- Commodities (cloth, herbs, ...) are grouped per item: the AH sells them by
-- unit and pulls from all your stacks. Other items (gear) are grouped per
-- link, because two copies can differ.
local _, ns = ...

local Bags = {}
ns.Bags = Bags

local FIRST_BAG, LAST_BAG = 0, 4

local function isCommodity(location)
  local status = C_AuctionHouse.GetItemCommodityStatus and C_AuctionHouse.GetItemCommodityStatus(location)
  return Enum and Enum.ItemCommodityStatus and status == Enum.ItemCommodityStatus.Commodity or false
end

--- @return list of { key, itemID, link, count, postable, isCommodity, bag, slot }
function Bags.sellable()
  if not (C_Container and C_AuctionHouse and _G.ItemLocation) then return {} end
  local byKey, list = {}, {}
  for bag = FIRST_BAG, LAST_BAG do
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
