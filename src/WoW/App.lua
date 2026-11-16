-- App: builds and connects every service. The UI and Main.lua only talk to this.
--
-- Responsibilities:
--   * owns the saved variables and settings
--   * knows which market (AH) prices to use right now
--   * builds the contexts the Core finders need from live game data
local _, ns = ...

local App = {}
App.__index = App
ns.App = App

local TOP_DEALS_SAVED = 5

--- @param saved the ForeverGoldDB saved-variables table (mutated)
--- @param clock function returning seconds
function App.new(saved, clock)
  saved.settings = ns.Settings.apply(saved.settings)
  saved.vendorPrices = saved.vendorPrices or {}
  saved.vendorItems = saved.vendorItems or {}
  saved.ui = saved.ui or {}
  saved.recipes = saved.recipes or {}

  local app = setmetatable({
    db = saved,
    settings = saved.settings,
    clock = clock,
    events = ns.Events.new(),
    charKey = ns.Api.characterKey(),
    lastOpportunities = {},
  }, App)

  app.prices = ns.PriceDB.new(saved, clock)
  app.loot = ns.LootDB.new(saved)
  app.scanner = ns.Scanner.new(app.prices, app.events, saved)
  app.session = ns.Session.new(clock, GetMoney and GetMoney() or 0)
  app.sellSearch = ns.SellSearch.new(function(item, listings)
    app.events:emit("sellSuggestion", item, app:suggest(item, listings), true)
  end, function(itemID, listings)
    app:recordLive(itemID, listings)
  end)
  app:refreshSkills()

  app.events:on("scanComplete", function(result) app:onScanComplete(result) end)
  return app
end

-- Markets --------------------------------------------------------------------

--- The market whose prices we use: the AH you're at, else your faction's AH.
function App:market()
  return ns.Market.current()
end

function App:value(itemID, marketKey)
  return self.prices:getValue(marketKey or self:market(), itemID)
end

--- The latest lowest AH price (from the last scan or a search today or
--- yesterday), which is what you'd see searching the item now. Falls back to
--- the market value when there's no recent price.
App.RECENT_DAYS = 1
function App:currentPrice(itemID, marketKey)
  local info = self.prices:getInfo(marketKey or self:market(), itemID)
  if info and info.ageDays <= App.RECENT_DAYS then return info.low end
  return info and info.value or nil
end

function App:history(itemID, marketKey)
  local info = self.prices:getInfo(marketKey or self:market(), itemID)
  return info and info.days or 0
end

--- Other AHs on the same realm with data, for arbitrage.
function App:otherMarkets(currentKey)
  local list = {}
  local realm = ns.Market.realmOf(currentKey)
  for _, key in ipairs(self.prices:markets()) do
    if key ~= currentKey and ns.Market.realmOf(key) == realm then
      list[#list + 1] = {
        key = key,
        label = ns.Market.label(key),
        cutRate = ns.Fees.cutRate(ns.Market.isNeutralKey(key)),
        value = function(id) return self:value(id, key) end,
        history = function(id) return self:history(id, key) end,
      }
    end
  end
  return list
end

-- Character ------------------------------------------------------------------

function App:refreshSkills()
  self.skills = ns.Professions.read()
end

function App:canDisenchant(item)
  return (self.skills.Enchanting or 0) >= ns.Disenchant.requiredSkill(item)
end

function App:recipes()
  return ns.TradeSkillRecorder.recipesFor(self.db, self.charKey)
end

function App:recordRecipes()
  local n = ns.TradeSkillRecorder.record(self.db, self.charKey)
  if n > 0 then self.events:emit("recipesUpdated", n) end
  return n
end

-- Valuation ------------------------------------------------------------------

function App:appraisal(marketKey)
  marketKey = marketKey or self:market()
  return ns.Appraisal.new({
    marketValue = function(id) return self:value(id, marketKey) end,
    itemInfo = ns.ItemInfo.get,
    isNeutral = ns.Market.isNeutralKey(marketKey),
    canDisenchant = function(item) return self:canDisenchant(item) end,
  })
end

--- What disenchanting an item would give, for characters with Enchanting.
--- @return nil (no Enchanting, or not disenchantable) or
---   { value (net after AH cut), complete, canDo, skillNeeded,
---     outcome = { {itemID, chance, min, max, price} } }
function App:disenchantEstimate(itemID)
  if not self.skills.Enchanting then return nil end
  local item = ns.ItemInfo.get(itemID)
  if not item or not ns.Disenchant.isDisenchantable(item) then return nil end
  local key, neutral = self:market()
  -- materials at today's prices, so it matches what a search shows
  local valueOf = function(id) return self:currentPrice(id, key) end
  local ev, complete = ns.Disenchant.expectedValue(item, valueOf)
  local outcome = {}
  for i, o in ipairs(ns.Disenchant.outcome(item)) do
    outcome[i] = { itemID = o.itemID, chance = o.chance, min = o.min, max = o.max, price = valueOf(o.itemID) }
  end
  local skillNeeded = ns.Disenchant.requiredSkill(item)
  return {
    value = ns.Fees.net(ev, neutral), complete = complete, outcome = outcome,
    skillNeeded = skillNeeded, canDo = self.skills.Enchanting >= skillNeeded,
  }
end

--- Best value of one item (auction, vendor or disenchant), 0 if unknown.
function App:valueOf(itemID)
  return self:appraisal():value(itemID)
end

function App:mobValue(npcID)
  local appraisal = self:appraisal()
  return self.loot:expectedValue(npcID, function(id) return appraisal:value(id) end)
end

function App:onItemsLooted(items)
  local appraisal = self:appraisal()
  for _, item in ipairs(items) do self.session:addLoot(appraisal:value(item.itemID) * item.qty) end
end

-- Auction house ---------------------------------------------------------------

function App:startScan()
  return self.scanner:start((self:market()))
end

function App:opportunityContext(result)
  local key, neutral = self:market()
  if result and result.marketKey then
    key, neutral = result.marketKey, ns.Market.isNeutralKey(result.marketKey)
  end
  return {
    listings = result and result.listings or {},
    value = function(id) return self:value(id, key) end,
    history = function(id) return self:history(id, key) end,
    itemInfo = ns.ItemInfo.get,
    vendorBuy = function(id) return self.db.vendorPrices[id] end,
    vendorItems = self.db.vendorItems,
    cutRate = ns.Fees.cutRate(neutral),
    settings = self.settings,
    skills = self.skills,
    recipes = self:recipes(),
    conversions = ns.Conversions.all(),
    otherMarkets = self:otherMarkets(key),
  }
end

function App:findOpportunities(result)
  result = result or self.scanner.lastResult
  local deals = ns.Opportunities.findAll(self:opportunityContext(result))
  self.lastOpportunities = deals
  local top = {}
  for i = 1, math.min(TOP_DEALS_SAVED, #deals) do
    local d = deals[i]
    top[i] = { kind = d.kind, itemID = d.itemID, profit = d.profit, name = d.name, note = d.note }
  end
  self.db.lastDeals = top
  self.events:emit("opportunitiesUpdated", deals)
  return deals
end

function App:onScanComplete(result)
  self.prices:prune(self.settings.historyDays)
  -- Vendor and disenchant deals need item details the client loads lazily.
  -- Ask for them now; onItemInfoReceived re-runs the finders as they arrive.
  if C_Item and C_Item.RequestLoadItemDataByID then
    for itemID in pairs(result.listings) do
      if not ns.ItemInfo.get(itemID) then C_Item.RequestLoadItemDataByID(itemID) end
    end
  end
  self:findOpportunities(result)
end

--- Called (debounced) when item data arrives from the server.
function App:onItemInfoReceived()
  if self.scanner.lastResult then self:findOpportunities(self.scanner.lastResult) end
end

--- Every essence conversion with its live profit or loss, for the Conversions view.
-- Inputs cost the cheapest listing from this session's scan (or market value).
function App:conversionRows()
  local key, neutral = self:market()
  local result = self.scanner.lastResult
  local listings = result and result.marketKey == key and result.listings or {}
  local function buyPrice(id)
    local l = listings[id]
    return l and l[1] and l[1].price or self:value(id, key)
  end
  local function sellValue(id)
    local v = self:value(id, key)
    return v and ns.Fees.net(v, neutral) or nil
  end
  return ns.Conversions.evaluateAll(ns.Conversions.all(), buyPrice, sellValue)
end

--- A search (yours or Blizzard's) returned every current listing of one item:
--- make it today's price snapshot and the item's listings for deal finding.
function App:recordLive(itemID, listings)
  local key = self:market()
  local recorded = self.prices:recordItem(key, itemID, listings)
  local result = self.scanner.lastResult
  if result and result.marketKey == key then
    result.listings[itemID] = recorded -- nil when nothing is listed any more
  end
  self.events:emit("pricesUpdated", itemID)
end

--- Profit or loss of every known recipe at current market prices.
function App:craftRows()
  local key, neutral = self:market()
  local ctx = {
    buyPrice = function(id) return self:value(id, key) end,
    vendorBuy = function(id) return self.db.vendorPrices[id] end,
    sellValue = function(id)
      local v = self:value(id, key)
      return v and ns.Fees.net(v, neutral) or nil
    end,
  }
  return ns.Crafting.evaluateAll(self:recipes(), ctx)
end

-- Selling ---------------------------------------------------------------------

--- Suggested price for an item from bags. `listings` are live search results;
--- without them, the listings from this session's scan are used.
function App:suggest(item, listings)
  local key, neutral = self:market()
  if not listings then
    local result = self.scanner.lastResult
    listings = {}
    for i, l in ipairs(result and result.marketKey == key and result.listings[item.itemID] or {}) do
      listings[i] = { price = l.price, count = l.count, mine = false }
    end
  end
  local info = ns.ItemInfo.get(item.itemID)
  local de = self:disenchantEstimate(item.itemID)
  return ns.SellPricing.suggest({
    listings = listings,
    value = self:value(item.itemID, key),
    historyDays = self:history(item.itemID, key),
    vendorSell = info and info.sellPrice or 0,
    disenchantValue = de and de.canDo and de.value > 0 and de.value or nil,
    cutRate = ns.Fees.cutRate(neutral),
    settings = self.settings,
  })
end

local ACTION_ORDER = { post = 1, disenchant = 2, vendor = 3, manual = 4 }

--- Everything in your bags that can go on the AH, with a suggested price,
--- most valuable first.
function App:sellRows()
  local rows = {}
  for _, item in ipairs(ns.Bags.sellable()) do
    local s = self:suggest(item)
    rows[#rows + 1] = { item = item, suggestion = s, total = (s.price or 0) * item.postable }
  end
  table.sort(rows, function(a, b)
    local oa, ob = ACTION_ORDER[a.suggestion.action], ACTION_ORDER[b.suggestion.action]
    if oa ~= ob then return oa < ob end
    if a.total ~= b.total then return a.total > b.total end
    return tostring(a.item.key) < tostring(b.item.key)
  end)
  return rows
end

-- Vendors ---------------------------------------------------------------------

function App:merchantDeals()
  local items = ns.Merchant.read()
  ns.Merchant.recordPrices(items, self.db.vendorPrices)
  ns.Merchant.recordStock(items, self.db.vendorItems, UnitName("npc"), GetZoneText and GetZoneText())
  local key, neutral = self:market()
  return ns.VendorAnalysis.evaluate(items, {
    value = function(id) return self:value(id, key) end,
    history = function(id) return self:history(id, key) end,
    cutRate = ns.Fees.cutRate(neutral),
    settings = self.settings,
  })
end

-- Home screen -----------------------------------------------------------------

function App:homeState()
  local mobs, recipes = 0, 0
  for _ in pairs(self.db.mobs) do mobs = mobs + 1 end
  for _ in pairs(self.db.recipes) do recipes = recipes + 1 end
  local lastScan = self.prices:lastScan((self:market()))
  return { scanned = lastScan ~= nil, lastScan = lastScan, mobsLearned = mobs, recipesKnown = recipes }
end

function App:topMobs(limit)
  local appraisal = self:appraisal()
  return self.loot:topMobs(function(id) return appraisal:value(id) end, self.settings.mobMinKills, limit)
end
