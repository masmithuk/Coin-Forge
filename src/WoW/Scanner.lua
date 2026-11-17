-- Scanner: full auction house scan via C_AuctionHouse.ReplicateItems.
--
-- The server allows one full scan every 15 minutes per realm. On WoW Forever each
-- ruleset (PvE, PvP...) is its own realm, so the cooldown is tracked per realm:
-- scanning on a PvE character never blocks a PvP one. A realm's faction and
-- neutral auction houses share it. Results are processed in batches across
-- frames so the client never freezes.
--
-- Events emitted on the bus:
--   "scanStarted"   (marketKey)
--   "scanProgress"  (done, total)
--   "scanComplete"  (result)  result = PriceDB commit result
local _, ns = ...

local Scanner = {}
Scanner.__index = Scanner
ns.Scanner = Scanner

Scanner.COOLDOWN = 15 * 60
Scanner.BATCH = 1000

-- Return positions of C_AuctionHouse.GetReplicateItemInfo
local COUNT, BUYOUT, ITEM_ID = 3, 10, 17

--- @param prices PriceDB
--- @param events Events bus
--- @param db persisted table (remembers each realm's last scan time across reloads)
function Scanner.new(prices, events, db)
  db.scanner = db.scanner or {}
  db.scanner.lastStart = nil -- the old account-wide cooldown, no longer used
  db.scanner.byRealm = db.scanner.byRealm or {}
  return setmetatable({ prices = prices, events = events, state = db.scanner, running = false }, Scanner)
end

local function realmOf(marketKey)
  return ns.Market.realmOf(marketKey or "") or marketKey or "?"
end

function Scanner.isSupported()
  return ns.Api.has("C_AuctionHouse.ReplicateItems")
end

--- Seconds until the next scan is allowed on this market's realm (0 if now).
function Scanner:cooldownLeft(marketKey)
  local last = self.state.byRealm[realmOf(marketKey)]
  if not last then return 0 end
  return math.max(0, Scanner.COOLDOWN - (time() - last))
end

--- Forgets every realm's cooldown (for tests).
function Scanner:resetCooldowns()
  self.state.byRealm = {}
end

--- Starts a scan. Returns true, or false plus seconds to wait / a reason.
function Scanner:start(marketKey)
  if self.running then return false, "running" end
  if not Scanner.isSupported() then return false, "unsupported" end
  local wait = self:cooldownLeft(marketKey)
  if wait > 0 then return false, wait end
  self.running = true
  self.marketKey = marketKey
  self.state.byRealm[realmOf(marketKey)] = time()
  self.events:emit("scanStarted", marketKey)
  C_AuctionHouse.ReplicateItems()
  return true
end

function Scanner:onEvent(event)
  if event == "REPLICATE_ITEM_LIST_UPDATE" and self.running and not self.scan then
    self:process()
  end
end

function Scanner:process()
  local total = C_AuctionHouse.GetNumReplicateItems()
  self.scan = self.prices:beginScan(self.marketKey)
  local index = 0

  local function step()
    local last = math.min(index + Scanner.BATCH, total) - 1
    for i = index, last do
      local info = { C_AuctionHouse.GetReplicateItemInfo(i) }
      local count, buyout, itemID = info[COUNT], info[BUYOUT], info[ITEM_ID]
      if itemID and buyout and buyout > 0 and count and count > 0 then
        self.scan:add(itemID, math.floor(buyout / count), count)
      end
    end
    index = last + 1
    self.events:emit("scanProgress", index, total)
    if index < total then
      C_Timer.After(0, step)
    else
      self:finish()
    end
  end

  step()
end

function Scanner:finish()
  local result = self.scan:commit()
  self.scan = nil
  self.running = false
  self.lastResult = result
  self.events:emit("scanComplete", result)
end
