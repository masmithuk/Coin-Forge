-- Appraisal: what one item is worth to you, and the best thing to do with it.
--
-- Used by tooltips ("best action"), mob loot value and bag valuation.
local _, ns = ...

local Appraisal = {}
Appraisal.__index = Appraisal
ns.Appraisal = Appraisal

--- @param deps table
--   marketValue(itemID) -> gross AH value or nil
--   itemInfo(itemID)    -> { quality, itemLevel, classID, sellPrice } or nil
--   isNeutral           -> whether the current AH is the neutral one (15% cut)
--   canDisenchant(item) -> whether this character can disenchant it
function Appraisal.new(deps)
  return setmetatable({ deps = deps }, Appraisal)
end

local function net(self, gross)
  return ns.Fees.net(gross, self.deps.isNeutral)
end

--- @return { auction = net|nil, vendor = copper|nil, disenchant = net|nil }
function Appraisal:options(itemID)
  local d = self.deps
  local options = {}
  local value = d.marketValue(itemID)
  if value then options.auction = net(self, value) end

  local item = d.itemInfo(itemID)
  if item and item.sellPrice and item.sellPrice > 0 then options.vendor = item.sellPrice end

  if item and ns.Disenchant.isDisenchantable(item) and d.canDisenchant(item) then
    local ev = ns.Disenchant.expectedValue(item, d.marketValue)
    if ev and ev > 0 then options.disenchant = net(self, ev) end
  end
  return options
end

--- @return action ("auction"|"vendor"|"disenchant") and its value, or nil
function Appraisal:best(itemID)
  local bestAction, bestValue
  for action, value in pairs(self:options(itemID)) do
    if not bestValue or value > bestValue then bestAction, bestValue = action, value end
  end
  return bestAction, bestValue
end

--- Best value in copper, 0 if unknown. Handy as a valueOf() function.
function Appraisal:value(itemID)
  local _, value = self:best(itemID)
  return value or 0
end
