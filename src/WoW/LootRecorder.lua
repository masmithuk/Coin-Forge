-- LootRecorder: feeds LootDB (mobs) and GatherDB (veins, herbs) from the loot window.
--
-- On LOOT_OPENED we snapshot every slot and its sources (and count kills and
-- gathers). Loot is only recorded when a slot is actually taken
-- (LOOT_SLOT_CLEARED), so re-opening a half-looted corpse can't double count.
--
-- Gathering is recognised from the spell you cast just before the loot window
-- opens (UNIT_SPELLCAST_SENT gives the spell and the target's name):
--   Mining / Herb Gathering on a world object -> one gather of that node, by name
--   Skinning on a corpse                      -> that mob's skinning stats
-- Loot from objects you didn't gather (chests, quest objects) is ignored.
local _, ns = ...

local LootRecorder = {}
LootRecorder.__index = LootRecorder
ns.LootRecorder = LootRecorder

local SLOT_ITEM, SLOT_MONEY = 1, 2
local CAST_WINDOW = 10 -- seconds from casting to the loot window opening

-- Gathering spell names (enUS) -> profession.
LootRecorder.GATHER_SPELLS = {
  ["Mining"] = "Mining",
  ["Herb Gathering"] = "Herbalism",
  ["Herbalism"] = "Herbalism",
  ["Skinning"] = "Skinning",
}

--- @param lootDB LootDB
--- @param onItemsLooted function({ {itemID, qty} }) for the session tracker (optional)
--- @param gatherDB GatherDB (optional)
function LootRecorder.new(lootDB, onItemsLooted, gatherDB)
  return setmetatable({ loot = lootDB, gather = gatherDB, onItemsLooted = onItemsLooted, slots = {} },
    LootRecorder)
end

local function spellName(spellID)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
  if GetSpellInfo then return (GetSpellInfo(spellID)) end
  return nil
end

--- The gathering cast this loot window belongs to, if it was recent.
function LootRecorder:recentGather()
  local g = self.lastGather
  if g and GetTime() - g.time <= CAST_WINDOW then return g end
  return nil
end

function LootRecorder:onCast(unit, target, spellID)
  if unit ~= "player" or ns.isSecret(target) or ns.isSecret(spellID) then return end
  local kind = LootRecorder.GATHER_SPELLS[spellName(spellID) or ""]
  if kind then
    self.lastGather = { kind = kind, target = target, time = GetTime() }
  end
end

-- Sources of one loot slot, each tagged with what it is:
--   { guid, qty, npcID, skin = bool }    a corpse (looted or skinned)
--   { guid, qty, node = name, kind }      a gathered vein or herb
local function sourcesOf(self, slot)
  local raw = { GetLootSourceInfo(slot) }
  local gather = self:recentGather()
  local sources = {}
  for i = 1, #raw, 2 do
    local guid, qty = raw[i], raw[i + 1] or 0
    local npcID = ns.GUID.npcID(guid)
    if npcID then
      -- skinning loot, if Skinning was cast on this kind of mob (its name, when known, must match)
      local m = self.loot:get(npcID)
      local skin = gather ~= nil and gather.kind == "Skinning"
        and (not m or not m.name or m.name == gather.target)
      sources[#sources + 1] = { guid = guid, qty = qty, npcID = npcID, skin = skin }
    elseif ns.GUID.isObject(guid) and gather and gather.kind ~= "Skinning" and gather.target and self.gather then
      sources[#sources + 1] = { guid = guid, qty = qty, node = gather.target, kind = gather.kind }
    end
  end
  return sources
end

local function record(self, source, items, copper)
  if source.node then
    self.gather:record(source.node, source.kind, source.guid, items)
  else
    self.loot:record(source.npcID, source.guid, items, copper, source.skin and { skin = true } or nil)
  end
end

function LootRecorder:opened()
  self.slots = {}
  for slot = 1, GetNumLootItems() do
    local kind = GetLootSlotType(slot)
    local entry = { kind = kind, sources = sourcesOf(self, slot) }
    if kind == SLOT_ITEM then entry.itemID = ns.Api.itemIDFromLink(GetLootSlotLink(slot)) end
    self.slots[slot] = entry
    for _, s in ipairs(entry.sources) do record(self, s, {}, 0) end -- counts the kill / gather
  end
end

function LootRecorder:taken(slot)
  local entry = self.slots[slot]
  if not entry then return end
  self.slots[slot] = nil
  local total = 0
  for _, s in ipairs(entry.sources) do
    if entry.kind == SLOT_MONEY then
      record(self, s, {}, s.qty)
    elseif entry.kind == SLOT_ITEM and entry.itemID then
      record(self, s, { { itemID = entry.itemID, qty = s.qty } }, 0)
      total = total + s.qty
    end
  end
  if total > 0 and self.onItemsLooted then
    self.onItemsLooted({ { itemID = entry.itemID, qty = total } })
  end
end

function LootRecorder:onEvent(event, ...)
  if event == "LOOT_OPENED" then self:opened()
  elseif event == "LOOT_SLOT_CLEARED" then self:taken((...))
  elseif event == "LOOT_CLOSED" then
    self.slots = {}
    self.lastGather = nil
  elseif event == "UNIT_SPELLCAST_SENT" then
    local unit, target, _, spellID = ...
    self:onCast(unit, target, spellID)
  elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED"
    or event == "UNIT_SPELLCAST_FAILED_QUIET" then
    if (...) == "player" then self.lastGather = nil end
  end
end
