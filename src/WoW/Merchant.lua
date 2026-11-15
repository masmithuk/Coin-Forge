-- Merchant: reads the open vendor's stock and remembers vendor prices
-- (used as reagent costs when crafting).
local _, ns = ...

local Merchant = {}
ns.Merchant = Merchant

local function itemInfo(i)
  if GetMerchantItemInfo then
    local _, _, price, stack, available, _, _, extendedCost = GetMerchantItemInfo(i)
    return price, stack, available, extendedCost
  end
  local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
  if not info then return nil end
  return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
end

local function itemID(i)
  if GetMerchantItemID then return GetMerchantItemID(i) end
  return ns.Api.itemIDFromLink(GetMerchantItemLink and GetMerchantItemLink(i))
end

--- @return { {index, itemID, price, stack, available} } for gold-priced items
function Merchant.read()
  local list = {}
  for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
    local price, stack, available, extendedCost = itemInfo(i)
    local id = itemID(i)
    if id and price and price > 0 and not extendedCost then
      list[#list + 1] = { index = i, itemID = id, price = price, stack = stack or 1, available = available or -1 }
    end
  end
  return list
end

--- Stores the per-unit vendor price of every item in `list`.
function Merchant.recordPrices(list, vendorPrices)
  for _, m in ipairs(list) do
    vendorPrices[m.itemID] = math.floor(m.price / math.max(1, m.stack))
  end
end
