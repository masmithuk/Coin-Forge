-- Mover: makes Blizzard's auction house window movable, with the Coin Forge
-- panel docked to its right, and remembers where you put it.
--
-- Drag the auction house window, or the Coin Forge panel, and both move
-- together. The position is saved in CoinForgeDB and put back each time the
-- auction house opens, and whenever Blizzard re-lays out its windows.
-- `/cforge ah reset` hands the position back to Blizzard.
local _, ns = ...

local Mover = {}
ns.Mover = Mover

local function inCombat() return InCombatLockdown and InCombatLockdown() end

--- @param frame the window to move (AuctionHouseFrame)
--- @param store persisted table; store.point = { point, relativePoint, x, y }
--- @param handles other frames that also drag it (the Coin Forge panel)
function Mover.attach(frame, store, handles)
  local function start()
    if inCombat() then return end
    frame:StartMoving()
    frame.coinForgeMoving = true
  end
  local function stop()
    if not frame.coinForgeMoving then return end
    frame.coinForgeMoving = false
    frame:StopMovingOrSizing()
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end -- we keep the position, not the layout cache
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then store.point = { point, relativePoint, x, y } end
  end

  local frames = { frame }
  for _, h in ipairs(handles or {}) do frames[#frames + 1] = h end
  frame:SetMovable(true)
  for _, f in ipairs(frames) do
    if not f.coinForgeDrag then
      f.coinForgeDrag = true
      f:EnableMouse(true)
      f:RegisterForDrag("LeftButton")
      f:HookScript("OnDragStart", start)
      f:HookScript("OnDragStop", stop)
    end
  end
end

--- Puts the window where you left it (if you moved it) and keeps the docked
--- panel on screen.
function Mover.apply(frame, store, docked)
  if docked and frame.SetClampRectInsets then
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(0, -(docked:GetWidth() + 4), 0, 0)
  end
  local p = store.point
  if not p or inCombat() then return end
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

function Mover.reset(store)
  store.point = nil
end
