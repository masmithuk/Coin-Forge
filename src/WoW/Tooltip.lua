-- Tooltip: price lines on item tooltips and loot value on mob tooltips.
local _, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

local ACTION_LABELS = { auction = "Auction", vendor = "Vendor", disenchant = "Disenchant" }
local STALE_DAYS = 2

local function amount(value, count)
  local text = ns.Money.short(value)
  if count and count > 1 then text = text .. "  x" .. count .. " = " .. ns.Money.short(value * count) end
  return text
end

--- @param deps { info(itemID) -> PriceDB info, options(itemID), best(itemID) }
--- @return list of { left, right }
function Tooltip.itemLines(itemID, count, deps)
  local lines = {}
  local info = deps.info(itemID)
  if info then
    lines[#lines + 1] = { "AH value", amount(info.value, count) }
    lines[#lines + 1] = { "AH lowest", ns.Money.short(info.low) }
    if info.ageDays >= STALE_DAYS then
      lines[#lines + 1] = { ("Prices are %d days old"):format(info.ageDays), "" }
    end
  end
  local options = deps.options(itemID)
  if options.vendor then lines[#lines + 1] = { "Vendor", amount(options.vendor, count) } end
  Tooltip.disenchantLines(lines, deps.disenchant and deps.disenchant(itemID), deps.nameOf)
  local action, value = deps.best(itemID)
  if action and #lines > 1 then
    lines[#lines + 1] = { "Best: " .. ACTION_LABELS[action], ns.Money.short(value) }
  end
  return lines
end

--- Appends the disenchant estimate (see App:disenchantEstimate) and the
--- likely materials. Shown only to characters with Enchanting.
function Tooltip.disenchantLines(lines, e, nameOf)
  if not e then return end
  local label = e.canDo and "Disenchant (estimate)" or ("Disenchant (needs Enchanting %d)"):format(e.skillNeeded)
  local value = (e.value > 0) and ns.Money.short(e.value) or "no material prices yet"
  lines[#lines + 1] = { label, value }
  for _, o in ipairs(e.outcome) do
    local qty = o.min == o.max and tostring(o.min) or (o.min .. "-" .. o.max)
    local name = nameOf and nameOf(o.itemID) or "?"
    lines[#lines + 1] = {
      ("  %s %s (%d%%)"):format(qty, name, math.floor(o.chance * 100 + 0.5)),
      o.price and (ns.Money.short(o.price) .. " each") or "?",
    }
  end
end

--- @param deps { expected(npcID) -> ev, kills; topDrops(npcID) ; nameOf(itemID) }
function Tooltip.unitLines(npcID, deps)
  local ev, kills = deps.expected(npcID)
  if not ev then return {} end
  local lines = { { "Loot per kill", ("%s (%d kills)"):format(ns.Money.short(ev), kills) } }
  for _, drop in ipairs(deps.topDrops(npcID)) do
    local rate = drop.perKill < 1 and ("%d%%"):format(math.floor(drop.perKill * 100 + 0.5))
      or ("x%.1f"):format(drop.perKill)
    lines[#lines + 1] = { "  " .. (deps.nameOf(drop.itemID) or "?") .. " " .. rate, ns.Money.short(drop.value) }
  end
  return lines
end

local function addLines(tooltip, lines)
  if #lines == 0 then return end
  tooltip:AddLine("Coin Forge", 1, 0.82, 0)
  for _, l in ipairs(lines) do tooltip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1) end
end

--- Hooks the game tooltips. `deps` holds item and unit dependencies plus settings.
function Tooltip.install(deps)
  local function onItem(tooltip, itemID)
    if deps.settings.showTooltips and itemID then addLines(tooltip, Tooltip.itemLines(itemID, 1, deps.item)) end
  end
  local function onUnit(tooltip, guid)
    local npcID = ns.GUID.npcID(guid)
    if deps.settings.showTooltips and npcID then addLines(tooltip, Tooltip.unitLines(npcID, deps.unit)) end
  end

  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      onItem(tooltip, data and data.id)
    end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
      onUnit(tooltip, data and data.guid)
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
      local _, link = tooltip:GetItem()
      onItem(tooltip, ns.Api.itemIDFromLink(link))
    end)
    GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
      local _, unit = tooltip:GetUnit()
      onUnit(tooltip, unit and UnitGUID(unit))
    end)
  end
end
