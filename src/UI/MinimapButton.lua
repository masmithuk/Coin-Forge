-- MinimapButton: a coin on the minimap. Click opens the home screen; hover
-- explains what Coinwise does; drag moves it around the minimap.
local _, ns = ...

local MinimapButton = {}
MinimapButton.__index = MinimapButton
ns.MinimapButton = MinimapButton

local RADIUS = 105

--- Position on the minimap edge for an angle in degrees.
function MinimapButton.position(angle, radius)
  local r = math.rad(angle)
  return math.cos(r) * (radius or RADIUS), math.sin(r) * (radius or RADIUS)
end

--- Angle in degrees of point (x, y) relative to the minimap centre.
function MinimapButton.angleOf(x, y)
  return math.deg(math.atan2 and math.atan2(y, x) or math.atan(y, x)) % 360
end

--- Fills a tooltip with the explanation and live status. Shared with the
--- addon compartment menu so both say the same thing.
function MinimapButton.fillTooltip(tooltip, app)
  tooltip:AddLine("Coinwise", 1, 0.82, 0)
  tooltip:AddLine(ns.HomeModel.TAGLINE, 1, 1, 1, true)
  tooltip:AddLine(" ")
  tooltip:AddLine("- Deals tab next to the auction house", 0.8, 0.8, 0.8)
  tooltip:AddLine("- Coin over mobs worth farming", 0.8, 0.8, 0.8)
  tooltip:AddLine("- Green glow on profitable vendor items", 0.8, 0.8, 0.8)
  tooltip:AddLine("- Prices and best action in item tooltips", 0.8, 0.8, 0.8)
  tooltip:AddLine(" ")
  local state = app:homeState()
  tooltip:AddLine(ns.HomeModel.scanStatus(state.lastScan, app.clock()), 0.6, 0.6, 0.65, true)
  local s = app.session:summary(GetMoney and GetMoney() or 0)
  if s.total ~= 0 then
    tooltip:AddLine(("Session: %s per hour"):format(ns.Money.short(s.perHour)), 0.6, 0.6, 0.65)
  end
  tooltip:AddLine(" ")
  tooltip:AddLine("Click to open. Drag to move.", 0.5, 0.5, 0.5)
end

function MinimapButton.new(app, onClick)
  local self = setmetatable({ app = app, onClick = onClick }, MinimapButton)
  app.db.ui.minimap = app.db.ui.minimap or { angle = 200 }
  return self
end

function MinimapButton:Build()
  local minimap = _G.Minimap
  if not minimap then return nil end
  local b = CreateFrame("Button", "CoinwiseMinimapButton", minimap)
  self.button = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function() self.onClick() end)
  b:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
    MinimapButton.fillTooltip(GameTooltip, self.app)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnDragStart", function(btn)
    btn:SetScript("OnUpdate", function()
      local mx, my = minimap:GetCenter()
      local scale = minimap:GetEffectiveScale()
      local cx, cy = _G.GetCursorPosition()
      self.app.db.ui.minimap.angle = MinimapButton.angleOf(cx / scale - mx, cy / scale - my)
      self:Place()
    end)
  end)
  b:SetScript("OnDragStop", function(btn) btn:SetScript("OnUpdate", nil) end)
  self:Place()
  self:Apply()
  return b
end

function MinimapButton:Place()
  local x, y = MinimapButton.position(self.app.db.ui.minimap.angle)
  self.button:ClearAllPoints()
  self.button:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

--- Shows or hides the button to match the showMinimap setting.
function MinimapButton:Apply()
  if self.button then self.button:SetShown(self.app.settings.showMinimap) end
end
