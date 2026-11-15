-- Disenchant: what an item breaks into, what that's worth, and the skill needed.
-- Rules come from Data/Disenchant.lua.
local _, ns = ...

local Disenchant = {}
ns.Disenchant = Disenchant

local CLASS_WEAPON, CLASS_ARMOR = 2, 4
local QUALITY_UNCOMMON, QUALITY_RARE, QUALITY_EPIC = 2, 3, 4

local function band(bands, itemLevel)
  for _, b in ipairs(bands) do
    if itemLevel <= b.maxLevel then return b end
  end
  return nil
end

function Disenchant.isDisenchantable(item)
  if not item or not item.itemLevel then return false end
  local gear = item.classID == CLASS_WEAPON or item.classID == CLASS_ARMOR
  return gear and item.quality ~= nil and item.quality >= QUALITY_UNCOMMON and item.quality <= QUALITY_EPIC
end

local function output(spec, chance)
  return { itemID = spec[1], chance = chance, min = spec[2], max = spec[3] }
end

--- @return list of { itemID, chance, min, max } or nil
function Disenchant.outcome(item)
  if not Disenchant.isDisenchantable(item) then return nil end
  local data = ns.Data.Disenchant

  if item.quality == QUALITY_UNCOMMON then
    local b = band(data.uncommon, item.itemLevel)
    if not b then return nil end
    local dustChance, essenceChance, shardChance = b.chances[1], b.chances[2], b.chances[3]
    if item.classID == CLASS_WEAPON then dustChance, essenceChance = essenceChance, dustChance end
    local out = { output(b.dust, dustChance), output(b.essence, essenceChance) }
    if b.shard and shardChance > 0 then out[#out + 1] = output(b.shard, shardChance) end
    return out
  end

  local bands = item.quality == QUALITY_RARE and data.rare or data.epic
  local b = band(bands, item.itemLevel)
  if not b then return nil end
  local out = {}
  for _, o in ipairs(b.outputs) do out[#out + 1] = output(o, o[4]) end
  return out
end

function Disenchant.requiredSkill(item)
  local b = band(ns.Data.Disenchant.skill, item.itemLevel or 0)
  return b and b.skill or 0
end

--- Expected (gross) copper value of disenchanting one item.
--- @param valueOf function(itemID) -> copper or nil
--- @return ev, complete  complete is false if any material had no price.
function Disenchant.expectedValue(item, valueOf)
  local out = Disenchant.outcome(item)
  if not out then return nil end
  local ev, complete = 0, true
  for _, o in ipairs(out) do
    local price = valueOf(o.itemID)
    if price then
      ev = ev + o.chance * (o.min + o.max) / 2 * price
    else
      complete = false
    end
  end
  return math.floor(ev), complete
end
