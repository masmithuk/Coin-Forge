-- LootRecorder: feeds LootDB from the loot window.
--
-- On LOOT_OPENED we snapshot every slot and its source corpses (and count the
-- kills). Loot is only recorded when a slot is actually taken
-- (LOOT_SLOT_CLEARED), so re-opening a half-looted corpse can't double count.
local _, ns = ...

local LootRecorder = {}
LootRecorder.__index = LootRecorder
ns.LootRecorder = LootRecorder

local SLOT_ITEM, SLOT_MONEY = 1, 2

--- @param lootDB LootDB
--- @param onItemsLooted function({ {itemID, qty} }) for the session tracker (optional)
function LootRecorder.new(lootDB, onItemsLooted)
  return setmetatable({ loot = lootDB, onItemsLooted = onItemsLooted, slots = {} }, LootRecorder)
end

local function sourcesOf(slot)
  local raw = { GetLootSourceInfo(slot) }
  local sources = {}
  for i = 1, #raw, 2 do
    local npcID = ns.GUID.npcID(raw[i])
    if npcID then sources[#sources + 1] = { guid = raw[i], npcID = npcID, qty = raw[i + 1] or 0 } end
  end
  return sources
end

function LootRecorder:opened()
  self.slots = {}
  for slot = 1, GetNumLootItems() do
    local kind = GetLootSlotType(slot)
    local entry = { kind = kind, sources = sourcesOf(slot) }
    if kind == SLOT_ITEM then entry.itemID = ns.Api.itemIDFromLink(GetLootSlotLink(slot)) end
    self.slots[slot] = entry
    for _, s in ipairs(entry.sources) do self.loot:record(s.npcID, s.guid, {}, 0) end
  end
end

function LootRecorder:taken(slot)
  local entry = self.slots[slot]
  if not entry then return end
  self.slots[slot] = nil
  local total = 0
  for _, s in ipairs(entry.sources) do
    if entry.kind == SLOT_MONEY then
      self.loot:record(s.npcID, s.guid, {}, s.qty)
    elseif entry.kind == SLOT_ITEM and entry.itemID then
      self.loot:record(s.npcID, s.guid, { { itemID = entry.itemID, qty = s.qty } }, 0)
      total = total + s.qty
    end
  end
  if total > 0 and self.onItemsLooted then
    self.onItemsLooted({ { itemID = entry.itemID, qty = total } })
  end
end

function LootRecorder:onEvent(event, slot)
  if event == "LOOT_OPENED" then self:opened()
  elseif event == "LOOT_SLOT_CLEARED" then self:taken(slot)
  elseif event == "LOOT_CLOSED" then self.slots = {} end
end
