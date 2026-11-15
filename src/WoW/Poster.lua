-- Poster: creates an auction. Must run from a click (Blizzard requires a
-- hardware event), so it's only ever called by the Post button.
--
-- Gear is posted buyout-only, with no starting bid, so nobody can win it
-- cheaply with a low bid.
local _, ns = ...

local Poster = {}
ns.Poster = Poster

-- Auction lengths as the API numbers them; on WoW Forever 1/2/3 are 2/8/24 hours.
Poster.DURATIONS = {
  { value = 1, label = "2 h" },
  { value = 2, label = "8 h" },
  { value = 3, label = "24 h" },
}

function Poster.ready()
  local check = C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady
  return not check or check() == true
end

function Poster.deposit(item, duration, quantity)
  local ah = C_AuctionHouse
  if item.isCommodity and ah.CalculateCommodityDeposit then
    return ah.CalculateCommodityDeposit(item.itemID, duration, quantity) or 0
  elseif ah.CalculateItemDeposit then
    return ah.CalculateItemDeposit(ns.Bags.location(item), duration, quantity) or 0
  end
  return 0
end

-- Lets Blizzard's own "are you sure?" dialog work if the server asks for one.
local function cachePending(frameName, ...)
  local frame = _G.AuctionHouseFrame and _G.AuctionHouseFrame[frameName]
  if frame and frame.CachePendingPost then pcall(frame.CachePendingPost, frame, ...) end
end

--- @return true, or false and a reason
function Poster.post(item, unitPrice, quantity, duration)
  local location = ns.Bags.location(item)
  if not (C_Item and C_Item.DoesItemExist and C_Item.DoesItemExist(location)) then
    return false, "The item moved in your bags. Select it again."
  end
  if not Poster.ready() then return false, "The auction house is busy, try again in a moment." end
  local ah = C_AuctionHouse
  if item.isCommodity then
    if ah.PostCommodity(location, duration, quantity, unitPrice) then
      cachePending("CommoditiesSellFrame", location, duration, quantity, unitPrice)
    end
  else
    if ah.PostItem(location, duration, quantity, nil, unitPrice) then
      cachePending("ItemSellFrame", location, duration, quantity, nil, unitPrice)
    end
  end
  return true
end
