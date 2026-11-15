-- PriceDB: auction price history built from full AH scans.
--
-- Storage (lives in SavedVariables, so plain tables only):
--   db.markets[marketKey] = {
--     lastScan = <time>,
--     items = { [itemID] = { snaps = { {day=, low=, value=, qty=}, ... } } },
--   }
-- One snapshot per item per day. `value` is the 20th-percentile unit price of
-- that scan, so a single troll listing can't drag it around. The market value
-- of an item is the median of its most recent daily values.
local _, ns = ...

local PriceDB = {}
PriceDB.__index = PriceDB
ns.PriceDB = PriceDB

local DAY = 86400
PriceDB.VALUE_PERCENTILE = 0.20
PriceDB.VALUE_WINDOW_DAYS = 14

--- @param db table persisted storage (mutated)
--- @param clock function returning the current time in seconds
function PriceDB.new(db, clock)
  db.markets = db.markets or {}
  return setmetatable({ db = db, clock = clock }, PriceDB)
end

local function today(self) return math.floor(self.clock() / DAY) end

function PriceDB:market(key, create)
  local m = self.db.markets[key]
  if not m and create then
    m = { items = {} }
    self.db.markets[key] = m
  end
  return m
end

function PriceDB:markets()
  local keys = {}
  for key in pairs(self.db.markets) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

function PriceDB:lastScan(key)
  local m = self:market(key)
  return m and m.lastScan
end

-- Scan ----------------------------------------------------------------------

local Scan = {}
Scan.__index = Scan

--- Starts collecting listings for one market. Call scan:add() per listing and
--- scan:commit() at the end.
function PriceDB:beginScan(marketKey)
  return setmetatable({ owner = self, marketKey = marketKey, listings = {} }, Scan)
end

--- @param unitPrice copper per single item (buyout / stack size)
function Scan:add(itemID, unitPrice, count)
  if not itemID or not unitPrice or unitPrice <= 0 or not count or count <= 0 then return end
  local list = self.listings[itemID]
  if not list then
    list = {}
    self.listings[itemID] = list
  end
  list[#list + 1] = { price = unitPrice, count = count }
end

--- Writes daily snapshots and returns { listings = {[itemID] = sorted list}, itemCount = n }.
function Scan:commit()
  local owner = self.owner
  local m = owner:market(self.marketKey, true)
  local day = today(owner)
  local itemCount = 0
  for itemID, list in pairs(self.listings) do
    table.sort(list, function(a, b) return a.price < b.price end)
    local qty = 0
    for _, l in ipairs(list) do qty = qty + l.count end
    local snap = {
      day = day,
      low = list[1].price,
      value = ns.Stats.weightedPercentile(list, PriceDB.VALUE_PERCENTILE),
      qty = qty,
    }
    local item = m.items[itemID] or { snaps = {} }
    m.items[itemID] = item
    local last = item.snaps[#item.snaps]
    if last and last.day == day then
      item.snaps[#item.snaps] = snap
    else
      item.snaps[#item.snaps + 1] = snap
    end
    itemCount = itemCount + 1
  end
  m.lastScan = owner.clock()
  return { listings = self.listings, itemCount = itemCount, marketKey = self.marketKey }
end

-- Queries -------------------------------------------------------------------

local function itemRecord(self, key, itemID)
  local m = self:market(key)
  local item = m and m.items[itemID]
  if not item or #item.snaps == 0 then return nil end
  return item
end

--- Median of recent daily values, or nil if never seen.
function PriceDB:getValue(key, itemID)
  local item = itemRecord(self, key, itemID)
  if not item then return nil end
  local values = {}
  local first = math.max(1, #item.snaps - PriceDB.VALUE_WINDOW_DAYS + 1)
  for i = first, #item.snaps do values[#values + 1] = item.snaps[i].value end
  return math.floor(ns.Stats.median(values))
end

--- Full picture for tooltips and confidence checks.
--- Returns { value, low, qty, days, ageDays } or nil.
function PriceDB:getInfo(key, itemID)
  local item = itemRecord(self, key, itemID)
  if not item then return nil end
  local last = item.snaps[#item.snaps]
  return {
    value = self:getValue(key, itemID),
    low = last.low,
    qty = last.qty,
    days = #item.snaps,
    ageDays = today(self) - last.day,
  }
end

--- Drops snapshots older than maxDays; removes items left with none.
function PriceDB:prune(maxDays)
  local cutoff = today(self) - maxDays
  for _, m in pairs(self.db.markets) do
    for itemID, item in pairs(m.items) do
      local kept = {}
      for _, s in ipairs(item.snaps) do
        if s.day >= cutoff then kept[#kept + 1] = s end
      end
      if #kept == 0 then m.items[itemID] = nil else item.snaps = kept end
    end
  end
end
