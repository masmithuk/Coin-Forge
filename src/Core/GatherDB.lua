-- GatherDB: what gathering nodes yield (mining veins, herbs), learned from your
-- own gathering.
--
-- Storage (SavedVariables, shared by all your characters, since yields are the
-- same everywhere):
--   db.nodes[nodeName] = { kind = "Mining"|"Herbalism", gathers, drops = { [itemID] = totalQty } }
--
-- A gather is counted once per node GUID, so re-opening the same node's loot
-- window adds its loot without counting a second gather.
local _, ns = ...

local GatherDB = {}
GatherDB.__index = GatherDB
ns.GatherDB = GatherDB

local SEEN_LIMIT = 300

function GatherDB.new(db)
  db.nodes = db.nodes or {}
  return setmetatable({ db = db, seen = {}, seenOrder = {} }, GatherDB)
end

local function markSeen(self, guid)
  if self.seen[guid] then return false end
  self.seen[guid] = true
  local order = self.seenOrder
  order[#order + 1] = guid
  if #order > SEEN_LIMIT then self.seen[table.remove(order, 1)] = nil end
  return true
end

--- Records loot taken from one node.
--- @param kind profession used ("Mining", "Herbalism")
--- @param items list of { itemID, qty }
function GatherDB:record(name, kind, guid, items)
  local n = self.db.nodes[name]
  if not n then
    n = { kind = kind, gathers = 0, drops = {} }
    self.db.nodes[name] = n
  end
  n.kind = kind or n.kind
  if markSeen(self, guid) then n.gathers = n.gathers + 1 end
  for _, item in ipairs(items or {}) do
    n.drops[item.itemID] = (n.drops[item.itemID] or 0) + item.qty
  end
end

function GatherDB:get(name)
  return self.db.nodes[name]
end

--- Average copper value of one gather.
--- @return ev, gathers  or nil if never gathered
function GatherDB:expectedValue(name, valueOf)
  local n = self.db.nodes[name]
  if not n or n.gathers == 0 then return nil end
  local total = 0
  for itemID, qty in pairs(n.drops) do total = total + qty * valueOf(itemID) end
  return math.floor(total / n.gathers), n.gathers
end

--- A node's yields: average amount per gather and the value that adds.
function GatherDB:topDrops(name, valueOf, limit)
  local n = self.db.nodes[name]
  if not n or n.gathers == 0 then return {} end
  local list = {}
  for itemID, qty in pairs(n.drops) do
    local per = qty / n.gathers
    list[#list + 1] = { itemID = itemID, perGather = per, value = math.floor(per * valueOf(itemID)) }
  end
  table.sort(list, function(a, b) return a.value > b.value end)
  while #list > limit do table.remove(list) end
  return list
end

--- Most valuable node types gathered at least minGathers times.
function GatherDB:topNodes(valueOf, minGathers, limit)
  local list = {}
  for name, n in pairs(self.db.nodes) do
    if n.gathers >= minGathers then
      list[#list + 1] = { name = name, kind = n.kind, ev = self:expectedValue(name, valueOf), gathers = n.gathers }
    end
  end
  table.sort(list, function(a, b) return a.ev > b.ev end)
  while #list > limit do table.remove(list) end
  return list
end
