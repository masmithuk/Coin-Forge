-- History: what you did with Coin Forge's suggestions, and how it turned out.
--
-- A log per auction house (db.history[marketKey].entries, oldest first) of
--   buy        an AH or vendor purchase, tagged with the deal it came from (if any)
--   post       an auction you posted, with the price Coin Forge suggested
--   sold       some of an item's auctions sold (oldest post first)
--   expired    some of an item's auctions expired
--   vendorSale an item sold to a merchant
--
-- Replaying the log gives "rounds", each a suggestion and its outcome:
--   sell        one post: sold or not, and at what share of the suggested price
--   flip, vendorFlip, arbitrage   a tagged buy, paired with later AH sales of that item
--   vendor      a tagged buy, paired with later sales to a merchant
--   other kinds (craft, disenchant, conversion...) are only logged: they change the item
-- A round still open after `unsoldDays` counts as unsold (a loss at cost) until
-- the item sells, which corrects it. Deposits come back when an auction sells, so
-- only expired auctions' deposits count against you.
--
-- Nothing is deleted unless the player clears it. Clearing folds the cleared
-- rounds into weekly totals (db.history[marketKey].weekly) first, so the
-- summary never loses them.
local _, ns = ...

local History = {}
History.__index = History
ns.History = History

local Book = {}
Book.__index = Book
History.Book = Book

local DAY = 86400
local WEEK = 7 * DAY

-- Deal kinds paired with an outcome, by where the item is sold.
local SOLD_ON_AH = { flip = true, vendorFlip = true, arbitrage = true }
local SOLD_TO_VENDOR = { vendor = true }

function History.new(db, clock)
  db.history = db.history or {}
  return setmetatable({ db = db.history, clock = clock }, History)
end

--- The log of one auction house.
function History:market(marketKey)
  local data = self.db[marketKey]
  if not data then
    data = { entries = {}, weekly = {} }
    self.db[marketKey] = data
  end
  return setmetatable({ data = data, clock = self.clock }, Book)
end

-- Logging --------------------------------------------------------------------

local function add(self, entry)
  entry.t = self.clock()
  local entries = self.data.entries
  entries[#entries + 1] = entry
  return entry
end

--- @param deal { kind, profit, qty } the suggestion this buy came from, or nil
function Book:buy(itemID, qty, unitPrice, deal)
  return add(self, { e = "buy", id = itemID, q = qty, p = unitPrice,
    kind = deal and deal.kind, profit = deal and deal.profit, dealQty = deal and deal.qty })
end

--- @param suggested the unit price Coin Forge suggested, or nil
function Book:post(itemID, qty, unitPrice, suggested, deposit)
  return add(self, { e = "post", id = itemID, q = qty, p = unitPrice, s = suggested, d = deposit or 0 })
end

--- @param net total received after the cut, or nil to estimate it from the posts
function Book:sold(itemID, qty, net)
  return add(self, { e = "sold", id = itemID, q = qty, n = net })
end

function Book:expired(itemID, qty)
  return add(self, { e = "expired", id = itemID, q = qty })
end

function Book:vendorSale(itemID, qty, unitPrice)
  return add(self, { e = "vendorSale", id = itemID, q = qty, p = unitPrice })
end

--- Item IDs with auctions still listed, for matching "sold" messages by name.
function Book:openPostItems()
  local open = {}
  for _, r in ipairs(self:replay(0.05)) do
    if r.kind == "sell" and r.left > 0 then open[r.itemID] = true end
  end
  return open
end

--- Units of the oldest still-listed post of an item (what an "expired" message refers to).
function Book:oldestOpenLeft(itemID)
  for _, r in ipairs(self:replay(0.05)) do
    if r.kind == "sell" and r.itemID == itemID and r.left > 0 then return r.left end
  end
  return nil
end

--- Remembers a sale mail so reading the mailbox again doesn't count it twice.
--- @return true the first time a key is seen
function Book:firstSeenMail(key)
  local now = self.clock()
  local seen = self.data.mail or {}
  self.data.mail = seen
  for k, t in pairs(seen) do
    if now - t > 31 * DAY then seen[k] = nil end -- auction mail lasts 30 days
  end
  if seen[key] then return false end
  seen[key] = now
  return true
end

-- Replaying the log into rounds ------------------------------------------------

local function newRound(kind, entry)
  return { kind = kind, itemID = entry.id, start = entry.t, refs = { [entry] = true } }
end

local function queueFor(map, id)
  local q = map[id]
  if not q then
    q = {}
    map[id] = q
  end
  return q
end

local function oldestOpen(list, field)
  for _, r in ipairs(list or {}) do
    if r[field] < r.qty then return r end
  end
  return nil
end

-- Hands out `units` (worth `value` in total) to buys of this item, oldest first.
local function pair(buys, entry, units, value)
  for _, b in ipairs(buys or {}) do
    if units <= 0 then return end
    local take = math.min(b.qty - b.paired, units)
    if take > 0 then
      b.paired = b.paired + take
      b.revenue = b.revenue + value * take / units
      value = value - value * take / units
      units = units - take
      b.refs[entry] = true
    end
  end
end

--- All rounds, without statuses (internal).
function Book:replay(cut)
  local rounds = {}
  local posts, ahBuys, vendorBuys = {}, {}, {}

  for _, entry in ipairs(self.data.entries) do
    local id = entry.id
    if entry.e == "buy" and entry.kind then
      local r = newRound(entry.kind, entry)
      r.qty, r.cost, r.paired, r.revenue, r.lost = entry.q, entry.p * entry.q, 0, 0, 0
      r.predicted = (entry.profit or 0) * entry.q / ((entry.dealQty or 0) > 0 and entry.dealQty or entry.q)
      if SOLD_ON_AH[entry.kind] then
        local q = queueFor(ahBuys, id)
        q[#q + 1] = r
      elseif SOLD_TO_VENDOR[entry.kind] then
        local q = queueFor(vendorBuys, id)
        q[#q + 1] = r
      else
        r.logged = true
      end
      rounds[#rounds + 1] = r
    elseif entry.e == "post" then
      local r = newRound("sell", entry)
      r.qty, r.left, r.price, r.suggested, r.deposit = entry.q, entry.q, entry.p, entry.s, entry.d or 0
      r.soldQty, r.expiredQty, r.net, r.lost, r.ratioSum, r.ratioQty = 0, 0, 0, 0, 0, 0
      r.predicted = (entry.s or entry.p) * entry.q * (1 - cut)
      local q = queueFor(posts, id)
      q[#q + 1] = r
      rounds[#rounds + 1] = r
    elseif entry.e == "sold" then
      local units, matched, value = entry.q, 0, 0
      for _, p in ipairs(posts[id] or {}) do
        if units <= 0 then break end
        local take = math.min(p.left, units)
        if take > 0 then
          local n = entry.n and entry.n * take / entry.q or p.price * take * (1 - cut)
          p.left, p.soldQty, p.net = p.left - take, p.soldQty + take, p.net + n
          if p.suggested and p.suggested > 0 then
            p.ratioSum = p.ratioSum + p.price / p.suggested * take
            p.ratioQty = p.ratioQty + take
          end
          p.refs[entry] = true
          units, matched, value = units - take, matched + take, value + n
        end
      end
      if matched > 0 then pair(ahBuys[id], entry, matched, value) end
    elseif entry.e == "expired" then
      local units = entry.q
      for _, p in ipairs(posts[id] or {}) do
        if units <= 0 then break end
        local take = math.min(p.left, units)
        if take > 0 then
          local lost = p.deposit * take / p.qty
          p.left, p.expiredQty, p.lost = p.left - take, p.expiredQty + take, p.lost + lost
          p.refs[entry] = true
          local buy = oldestOpen(ahBuys[id], "paired")
          if buy then
            buy.lost = buy.lost + lost
            buy.refs[entry] = true
          end
          units = units - take
        end
      end
    elseif entry.e == "vendorSale" then
      pair(vendorBuys[id], entry, entry.q, entry.p * entry.q)
    end
  end
  return rounds
end

--- Rounds with their outcome.
--- @param opts { unsoldDays = 14, cut = 0.05 }
--- @return list of { kind, itemID, start, predicted, actual, status = "sold"|"unsold"|"open"|"logged" }
function Book:rounds(opts)
  local now, wait = self.clock(), (opts.unsoldDays or 14) * DAY
  local rounds = self:replay(opts.cut or 0.05)
  for _, r in ipairs(rounds) do
    local old = now - r.start >= wait
    if r.logged then
      r.status = "logged"
    elseif r.kind == "sell" then
      r.actual = r.net - r.lost
      if r.left > 0 and not old then r.status = "open"
      else r.status = r.soldQty > 0 and "sold" or "unsold" end
    else
      r.actual = r.revenue - r.cost - r.lost
      if r.paired >= r.qty then r.status = "sold"
      elseif not old then r.status = "open"
      else r.status = r.paired > 0 and "sold" or "unsold" end
    end
  end
  return rounds
end

-- Summaries ------------------------------------------------------------------

local SUMS = { "rounds", "sold", "unsold", "logged", "predicted", "soldQty", "expiredQty", "ratioSum", "ratioQty" }

local function accumulate(totals, r)
  if r.status == "logged" then
    totals.logged = (totals.logged or 0) + 1
    totals.predicted = (totals.predicted or 0) + r.predicted
    return
  end
  totals.rounds = (totals.rounds or 0) + 1
  totals[r.status] = (totals[r.status] or 0) + 1
  totals.predicted = (totals.predicted or 0) + r.predicted
  totals.actual = (totals.actual or 0) + r.actual
  if r.kind == "sell" then
    totals.soldQty = (totals.soldQty or 0) + r.soldQty
    totals.expiredQty = (totals.expiredQty or 0) + r.expiredQty
    totals.ratioSum = (totals.ratioSum or 0) + r.ratioSum
    totals.ratioQty = (totals.ratioQty or 0) + r.ratioQty
  end
end

local function merge(into, from)
  for _, k in ipairs(SUMS) do
    if from[k] then into[k] = (into[k] or 0) + from[k] end
  end
  if from.actual then into.actual = (into.actual or 0) + from.actual end
end

--- Predicted vs actual per suggestion kind, over everything ever logged.
--- @return { [kind] = { rounds, sold, unsold, open, logged, predicted, actual,
---   sellRate, vsSuggested (sell only) } }
function Book:summary(opts)
  local raw = {}
  local function bucket(kind)
    raw[kind] = raw[kind] or { open = 0 }
    return raw[kind]
  end
  for _, kinds in pairs(self.data.weekly) do
    for kind, totals in pairs(kinds) do merge(bucket(kind), totals) end
  end
  for _, r in ipairs(self:rounds(opts)) do
    local b = bucket(r.kind)
    if r.status == "open" then b.open = b.open + 1 else accumulate(b, r) end
  end

  local out = {}
  for kind, t in pairs(raw) do
    local s = {
      rounds = t.rounds or 0, sold = t.sold or 0, unsold = t.unsold or 0, open = t.open,
      logged = t.logged or 0, predicted = math.floor(t.predicted or 0),
      actual = t.actual and math.floor(t.actual) or nil,
    }
    local resolved = (t.soldQty or 0) + (t.expiredQty or 0)
    if resolved > 0 then s.sellRate = t.soldQty / resolved end
    if (t.ratioQty or 0) > 0 then s.vsSuggested = t.ratioSum / t.ratioQty end
    out[kind] = s
  end
  return out
end

-- Keeping it tidy ------------------------------------------------------------

--- Removes finished rounds that started more than `days` ago (nil = all
--- finished rounds), after adding them to the weekly totals. Rounds still open
--- (listed and younger than unsoldDays) keep their entries.
--- @return number of entries removed
function Book:clear(days, opts)
  local now = self.clock()
  local cutoff = days and (now - days * DAY) or math.huge
  local rounds = self:rounds(opts)

  local users = {}
  local candidate = {}
  for _, r in ipairs(rounds) do
    candidate[r] = r.status ~= "open" and r.start < cutoff
    for entry in pairs(r.refs) do
      users[entry] = users[entry] or {}
      table.insert(users[entry], r)
    end
  end
  -- a round can only go if every round sharing its entries goes too
  local changed = true
  while changed do
    changed = false
    for _, r in ipairs(rounds) do
      if candidate[r] then
        for entry in pairs(r.refs) do
          for _, other in ipairs(users[entry]) do
            if not candidate[other] then
              candidate[r] = false
              changed = true
            end
          end
        end
      end
    end
  end

  local remove = {}
  for _, r in ipairs(rounds) do
    if candidate[r] then
      local week = math.floor(r.start / WEEK)
      local kinds = self.data.weekly[week] or {}
      self.data.weekly[week] = kinds
      kinds[r.kind] = kinds[r.kind] or {}
      accumulate(kinds[r.kind], r)
      for entry in pairs(r.refs) do remove[entry] = true end
    end
  end

  local kept, removed = {}, 0
  for _, entry in ipairs(self.data.entries) do
    -- entries no round uses (untagged buys, unmatched sales) go once old enough
    if remove[entry] or (not users[entry] and entry.t < cutoff) then
      removed = removed + 1
    else
      kept[#kept + 1] = entry
    end
  end
  self.data.entries = kept
  return removed
end

--- Advice to clear the log, or nil while it's small and recent.
--- @param limits { entries = n, days = n }
--- @return { entries = n, oldestDays = n } or nil
function Book:tidyAdvice(limits)
  local entries = self.data.entries
  local oldest = entries[1]
  local oldestDays = oldest and math.floor((self.clock() - oldest.t) / DAY) or 0
  if #entries >= limits.entries or (oldest and oldestDays >= limits.days) then
    return { entries = #entries, oldestDays = oldestDays }
  end
  return nil
end
