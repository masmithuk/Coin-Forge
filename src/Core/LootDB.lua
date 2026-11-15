-- LootDB: what each kind of mob drops, learned from your own looting.
--
-- Storage (SavedVariables, shared by all your characters):
--   db.mobs[npcID] = { name, kills, copper, drops = { [itemID] = totalQty } }
--
-- A kill is counted once per mob GUID, so skinning or re-opening the same
-- corpse adds its loot without inflating the kill count.
local _, ns = ...

local LootDB = {}
LootDB.__index = LootDB
ns.LootDB = LootDB

local SEEN_LIMIT = 500

function LootDB.new(db)
  db.mobs = db.mobs or {}
  return setmetatable({ db = db, seen = {}, seenOrder = {} }, LootDB)
end

local function mob(self, npcID)
  local m = self.db.mobs[npcID]
  if not m then
    m = { kills = 0, copper = 0, drops = {} }
    self.db.mobs[npcID] = m
  end
  return m
end

local function markSeen(self, guid)
  if self.seen[guid] then return false end
  self.seen[guid] = true
  local order = self.seenOrder
  order[#order + 1] = guid
  if #order > SEEN_LIMIT then
    self.seen[table.remove(order, 1)] = nil
  end
  return true
end

function LootDB:setName(npcID, name)
  if npcID and name then mob(self, npcID).name = name end
end

--- Records the loot taken from one corpse.
--- @param items list of { itemID, qty }
--- @param copper coin looted from it
function LootDB:record(npcID, guid, items, copper)
  local m = mob(self, npcID)
  if markSeen(self, guid) then m.kills = m.kills + 1 end
  m.copper = m.copper + (copper or 0)
  for _, item in ipairs(items or {}) do
    m.drops[item.itemID] = (m.drops[item.itemID] or 0) + item.qty
  end
end

function LootDB:get(npcID)
  return self.db.mobs[npcID]
end

--- Average copper value per kill.
--- @param valueOf function(itemID) -> copper (e.g. Appraisal:value)
--- @return ev, kills  or nil if never killed
function LootDB:expectedValue(npcID, valueOf)
  local m = self.db.mobs[npcID]
  if not m or m.kills == 0 then return nil end
  local total = m.copper
  for itemID, qty in pairs(m.drops) do total = total + qty * valueOf(itemID) end
  return math.floor(total / m.kills), m.kills
end

--- Most valuable mobs with at least minKills recorded.
function LootDB:topMobs(valueOf, minKills, limit)
  local list = {}
  for npcID, m in pairs(self.db.mobs) do
    if m.kills >= minKills then
      local ev = self:expectedValue(npcID, valueOf)
      list[#list + 1] = { npcID = npcID, name = m.name, ev = ev, kills = m.kills }
    end
  end
  table.sort(list, function(a, b) return a.ev > b.ev end)
  while #list > limit do table.remove(list) end
  return list
end

--- A mob's drops ordered by value contributed per kill.
function LootDB:topDrops(npcID, valueOf, limit)
  local m = self.db.mobs[npcID]
  if not m or m.kills == 0 then return {} end
  local list = {}
  for itemID, qty in pairs(m.drops) do
    local perKill = qty / m.kills
    list[#list + 1] = { itemID = itemID, perKill = perKill, value = math.floor(perKill * valueOf(itemID)) }
  end
  table.sort(list, function(a, b) return a.value > b.value end)
  while #list > limit do table.remove(list) end
  return list
end
