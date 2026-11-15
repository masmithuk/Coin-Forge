-- Nameplates: puts a coin and the expected loot value over profitable mobs.
local _, ns = ...

local Nameplates = {}
Nameplates.__index = Nameplates
ns.Nameplates = Nameplates

local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

function Nameplates.shouldMark(ev, kills, settings)
  return ev ~= nil and kills ~= nil and kills >= settings.mobMinKills and ev >= settings.mobMinValue
end

--- @param deps { settings, valueOf(npcID) -> ev, kills }
function Nameplates.new(deps)
  return setmetatable({ deps = deps, plates = {} }, Nameplates)
end

local function marker(plate)
  local m = plate.ForeverGoldMarker
  if m then return m end
  m = CreateFrame("Frame", nil, plate)
  m:SetSize(18, 18)
  m:SetPoint("BOTTOM", plate, "TOP", 0, 2)
  local icon = m:CreateTexture(nil, "OVERLAY")
  icon:SetAllPoints()
  icon:SetTexture(COIN_ICON)
  local label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", m, "RIGHT", 2, 0)
  m.label = label
  plate.ForeverGoldMarker = m
  return m
end

function Nameplates:update(unit)
  local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then return end
  self.plates[unit] = plate
  local settings = self.deps.settings
  local npcID = not UnitIsPlayer(unit) and ns.GUID.npcID(UnitGUID(unit))
  local ev, kills
  if npcID then ev, kills = self.deps.valueOf(npcID) end
  if settings.showNameplates and Nameplates.shouldMark(ev, kills, settings) then
    local m = marker(plate)
    m.label:SetText(ns.Money.short(ev))
    m:Show()
  elseif plate.ForeverGoldMarker then
    plate.ForeverGoldMarker:Hide()
  end
end

function Nameplates:refreshAll()
  for unit in pairs(self.plates) do self:update(unit) end
end

function Nameplates:onEvent(event, unit)
  if event == "NAME_PLATE_UNIT_ADDED" then
    self:update(unit)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    local plate = self.plates[unit]
    if plate and plate.ForeverGoldMarker then plate.ForeverGoldMarker:Hide() end
    self.plates[unit] = nil
  end
end
