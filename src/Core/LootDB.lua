-- LootDB: what each kind of mob drops, learned from your own looting.
--
-- Storage (SavedVariables, shared by all your characters):
--   db.mobs[npcID] = { name, kills, copper, drops = { [itemID] = totalQty },
--                      skins = { count, drops = { [itemID] = totalQty } } }
--
-- Skinning loot is kept apart in `skins` (counted per corpse skinned), so
-- "loot per kill" is what anyone gets and skinning is only added for
-- characters who can skin.
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
  return setmetatable({ db = db, seen = {}, seenOrder = {}, skinned = {}, skinnedOrder = {} }, LootDB)
end

local function mob(self, npcID)
  local m = self.db.mobs[npcID]
  if not m then
    m = { kills = 0, copper = 0, drops = {} }
    self.db.mobs[npcID] = m
  end
  return m
end

local function markSeen(self, guid, seenKey, orderKey)
  local seen, order = self[seenKey or "seen"], self[orderKey or "seenOrder"]
  if seen[guid] then return false end
  seen[guid] = true
  order[#order + 1] = guid
  if #order > SEEN_LIMIT then
    seen[table.remove(order, 1)] = nil
  end
  return true
end

function LootDB:setName(npcID, name)
  if npcID and name then mob(self, npcID).name = name end
end

--- Records the loot taken from one corpse.
--- @param items list of { itemID, qty }
--- @param copper coin looted from it
--- @param opts { skin = true } for loot from skinning the corpse
function LootDB:record(npcID, guid, items, copper, opts)
  local m = mob(self, npcID)
  if opts and opts.skin then
    m.skins = m.skins or { count = 0, drops = {} }
    if markSeen(self, guid, "skinned", "skinnedOrder") then m.skins.count = m.skins.count + 1 end
    for _, item in ipairs(items or {}) do
      m.skins.drops[item.itemID] = (m.skins.drops[item.itemID] or 0) + item.qty
    end
    return
  end
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

--- Average copper value of skinning one corpse of this mob.
--- @return ev, corpsesSkinned  or nil if never skinned
function LootDB:skinValue(npcID, valueOf)
  local m = self.db.mobs[npcID]
  local skins = m and m.skins
  if not skins or skins.count == 0 then return nil end
  local total = 0
  for itemID, qty in pairs(skins.drops) do total = total + qty * valueOf(itemID) end
  return math.floor(total / skins.count), skins.count
end

--- A mob's skinning yields per corpse, most valuable first.
function LootDB:topSkins(npcID, valueOf, limit)
  local m = self.db.mobs[npcID]
  local skins = m and m.skins
  if not skins or skins.count == 0 then return {} end
  local list = {}
  for itemID, qty in pairs(skins.drops) do
    local per = qty / skins.count
    list[#list + 1] = { itemID = itemID, perKill = per, value = math.floor(per * valueOf(itemID)) }
  end
  table.sort(list, function(a, b) return a.value > b.value end)
  while #list > limit do table.remove(list) end
  return list
end

--- Most valuable mobs with at least minKills recorded.
--- @param opts { includeSkins = bool } (optional) add skinning value per kill
function LootDB:topMobs(valueOf, minKills, limit, opts)
  local list = {}
  for npcID, m in pairs(self.db.mobs) do
    if m.kills >= minKills then
      local ev = self:expectedValue(npcID, valueOf)
      if opts and opts.includeSkins then ev = ev + (self:skinValue(npcID, valueOf) or 0) end
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
