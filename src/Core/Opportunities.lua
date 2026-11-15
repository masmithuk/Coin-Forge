-- Opportunities: ways to make money from the current auction listings.
--
-- Each finder is `function(ctx) -> { opportunity, ... }`. To add a new idea,
-- add a finder to Opportunities.finders - nothing else needs to change.
--
-- ctx fields:
--   listings[itemID]   current listings, cheapest first: { {price, count}, ... }
--   value(itemID)      gross market value on this AH, or nil
--   history(itemID)    days of price history on this AH
--   itemInfo(itemID)   { quality, itemLevel, classID, sellPrice } or nil
--   vendorBuy(itemID)  vendor purchase price if known, or nil
--   cutRate            AH cut on this AH (0.05 / 0.15)
--   settings           { minProfit, flipDiscount, minHistoryDays }
--   skills             { [professionName] = skill } for the current character
--   recipes            recipe list (see Crafting.lua)
--   conversions        conversion list (see Conversions.lua)
--   otherMarkets       { {key, label, cutRate, value(itemID), history(itemID)} }
--
-- An opportunity:
--   { kind, itemID, qty, maxPrice, cost, revenue, profit, canDo, note, name? }
local _, ns = ...

local Opportunities = {}
ns.Opportunities = Opportunities

local finders = {}
Opportunities.finders = finders

-- Display order of kinds (also used by the panel tabs).
Opportunities.KINDS = {
  "flip", "vendor", "vendorFlip", "conversion", "arbitrage", "disenchant", "craft", "craftInstead",
}

local function trusted(ctx, itemID, history)
  return (history or ctx.history)(itemID) >= ctx.settings.minHistoryDays
end

local function netOf(ctx, gross) return gross * (1 - ctx.cutRate) end

--- Walks listings cheapest first, buying every unit whose resale value beats its
--- price (and that passes `accept`), and returns totals.
local function buyWhileProfitable(listings, unitRevenue, accept)
  local qty, cost, maxPrice = 0, 0, nil
  for _, l in ipairs(listings) do
    if l.price >= unitRevenue or (accept and not accept(l.price)) then break end
    qty = qty + l.count
    cost = cost + l.price * l.count
    maxPrice = l.price
  end
  if qty == 0 then return nil end
  local revenue = math.floor(unitRevenue * qty)
  return { qty = qty, cost = cost, revenue = revenue, profit = revenue - cost, maxPrice = maxPrice }
end

local function emit(list, ctx, kind, itemID, deal, canDo, note)
  if not deal or deal.profit < ctx.settings.minProfit then return end
  deal.kind, deal.itemID, deal.canDo, deal.note = kind, itemID, canDo, note
  list[#list + 1] = deal
end

--- Flip: listings far enough under market value to resell.
function finders.flip(ctx)
  local list = {}
  for itemID, listings in pairs(ctx.listings) do
    local value = ctx.value(itemID)
    if value and trusted(ctx, itemID) then
      local threshold = value * (1 - ctx.settings.flipDiscount)
      local deal = buyWhileProfitable(listings, netOf(ctx, value), function(price) return price <= threshold end)
      emit(list, ctx, "flip", itemID, deal, true, "Relist near " .. ns.Money.short(value))
    end
  end
  return list
end

--- Vendor snipe: listings cheaper than what a vendor pays.
function finders.vendor(ctx)
  local list = {}
  for itemID, listings in pairs(ctx.listings) do
    local item = ctx.itemInfo(itemID)
    if item and item.sellPrice and item.sellPrice > 0 then
      emit(list, ctx, "vendor", itemID, buyWhileProfitable(listings, item.sellPrice), true, "Sell to any vendor")
    end
  end
  return list
end

--- Disenchant: gear cheaper than the materials it breaks into.
-- Hidden entirely for characters without Enchanting; enchanters whose skill is
-- too low still see them, marked with the skill needed.
function finders.disenchant(ctx)
  local list = {}
  if not ctx.skills.Enchanting then return list end
  for itemID, listings in pairs(ctx.listings) do
    local item = ctx.itemInfo(itemID)
    if item and ns.Disenchant.isDisenchantable(item) then
      local ev, complete = ns.Disenchant.expectedValue(item, ctx.value)
      if ev and complete and ev > 0 then
        local need = ns.Disenchant.requiredSkill(item)
        local canDo = (ctx.skills.Enchanting or 0) >= need
        local note = canDo and "Disenchant, sell the materials" or ("Needs Enchanting " .. need)
        emit(list, ctx, "disenchant", itemID, buyWhileProfitable(listings, netOf(ctx, ev)), canDo, note)
      end
    end
  end
  return list
end

--- Conversion: e.g. buy 3 lesser essences, combine, sell the greater one.
-- Buys input units cheapest first, one conversion at a time, while profitable.
-- Net revenue of one conversion's outputs, or nil if any output is unpriced.
local function outputRevenue(ctx, conv)
  local total = 0
  for _, out in ipairs(conv.outputs) do
    local v = ctx.value(out[1])
    if not v or not trusted(ctx, out[1]) then return nil end
    total = total + netOf(ctx, v) * out[2]
  end
  return total
end

-- A cursor over listings that hands out the cheapest remaining units.
local function unitQueue(listings)
  local queue = { index = 1, left = listings[1] and listings[1].count or 0 }
  -- Price of the next n units without consuming them, or nil if not enough.
  function queue.peek(n)
    local i, left, cost = queue.index, queue.left, 0
    for _ = 1, n do
      while listings[i] and left == 0 do
        i = i + 1
        left = listings[i] and listings[i].count or 0
      end
      if not listings[i] then return nil end
      cost = cost + listings[i].price
      left = left - 1
    end
    return cost, i, left
  end
  function queue.take(n)
    local cost, i, left = queue.peek(n)
    queue.index, queue.left = i, left
    return cost
  end
  return queue
end

function finders.conversion(ctx)
  local list = {}
  for _, conv in ipairs(ctx.conversions) do
    local input, perConversion = conv.inputs[1][1], conv.inputs[1][2]
    local listings = ctx.listings[input]
    local revenueEach = outputRevenue(ctx, conv)
    if listings and revenueEach and #conv.inputs == 1 then
      local queue = unitQueue(listings)
      local times, cost = 0, 0
      while true do
        local batch = queue.peek(perConversion)
        if not batch or batch >= revenueEach then break end
        cost = cost + queue.take(perConversion)
        times = times + 1
      end
      if times > 0 then
        local revenue = math.floor(revenueEach * times)
        emit(list, ctx, "conversion", input,
          { qty = times * perConversion, cost = cost, revenue = revenue, profit = revenue - cost, name = conv.name },
          true, conv.name .. " x" .. times)
      end
    end
  end
  return list
end

local function lowest(ctx, itemID)
  local l = ctx.listings[itemID]
  return l and l[1] and l[1].price or nil
end

local function crafterNote(recipe)
  if recipe.knownByPlayer then return "You know this recipe" end
  local names = recipe.crafters or {}
  if #names == 0 then return "Recipe not known" end
  return "Known by " .. table.concat(names, ", ")
end

--- Craft: buy reagents now, craft, sell the result.
function finders.craft(ctx)
  local list = {}
  local craftCtx = {
    buyPrice = function(id) return lowest(ctx, id) end,
    vendorBuy = ctx.vendorBuy,
    sellValue = function(id)
      local v = ctx.value(id)
      return v and trusted(ctx, id) and netOf(ctx, v) or nil
    end,
  }
  for _, recipe in ipairs(ctx.recipes) do
    local r = ns.Crafting.evaluate(recipe, craftCtx)
    if r.profit then
      emit(list, ctx, "craft", recipe.outputItemID,
        { qty = 1, cost = r.cost, revenue = r.revenue, profit = r.profit, name = recipe.name },
        recipe.knownByPlayer == true, crafterNote(recipe))
    end
  end
  return list
end

--- Craft instead: an item is listed for more than it costs you to make it.
-- `profit` is the saving versus buying the cheapest listing.
function finders.craftInstead(ctx)
  local list = {}
  local craftCtx = {
    buyPrice = function(id)
      local a, b = ctx.value(id), lowest(ctx, id)
      if a and b then return math.min(a, b) end
      return a or b
    end,
    vendorBuy = ctx.vendorBuy,
    sellValue = function() return nil end,
  }
  for _, recipe in ipairs(ctx.recipes) do
    local listed = lowest(ctx, recipe.outputItemID)
    if listed then
      local r = ns.Crafting.evaluate(recipe, craftCtx)
      if r.cost then
        local perUnit = r.cost / (recipe.outputQty or 1)
        local saving = math.floor(listed - perUnit)
        emit(list, ctx, "craftInstead", recipe.outputItemID,
          { qty = 1, cost = math.floor(perUnit), revenue = listed, profit = saving,
            maxPrice = listed, name = recipe.name },
          recipe.knownByPlayer == true,
          "Make it for " .. ns.Money.short(perUnit) .. ". " .. crafterNote(recipe))
      end
    end
  end
  return list
end

--- From vendor: items you've seen at a vendor that sell for more on the AH.
-- Suggests the whole limited stock, or one purchase of an unlimited item
-- (flooding the AH with an unlimited item just crashes its price).
-- ctx.vendorItems[itemID] = { price (per unit), stack, available, merchant, zone }
function finders.vendorFlip(ctx)
  local list = {}
  for itemID, v in pairs(ctx.vendorItems or {}) do
    local value = ctx.value(itemID)
    if value and v.price and v.price > 0 and trusted(ctx, itemID) then
      local perUnit = netOf(ctx, value) - v.price
      if perUnit > 0 then
        local qty = (v.available or -1) > 0 and v.available or (v.stack or 1)
        local where = v.merchant and ("Buy from " .. v.merchant .. (v.zone and (" in " .. v.zone) or ""))
          or "Buy from a vendor"
        if (v.available or -1) > 0 then where = where .. " (limited stock)" end
        emit(list, ctx, "vendorFlip", itemID,
          { qty = qty, cost = v.price * qty, revenue = math.floor(netOf(ctx, value) * qty),
            profit = math.floor(perUnit * qty), maxPrice = v.price },
          true, where)
      end
    end
  end
  return list
end

--- Arbitrage: buy here, sell on another auction house.
function finders.arbitrage(ctx)
  local list = {}
  for _, market in ipairs(ctx.otherMarkets) do
    for itemID, listings in pairs(ctx.listings) do
      local value = market.value(itemID)
      if value and trusted(ctx, itemID, market.history) then
        local deal = buyWhileProfitable(listings, value * (1 - market.cutRate))
        emit(list, ctx, "arbitrage", itemID, deal, true, "Sell on " .. market.label)
      end
    end
  end
  return list
end

--- Runs every finder (or the ones given), merges and sorts by profit.
-- A failing finder is skipped so one bug can't blank the whole page.
function Opportunities.findAll(ctx, only)
  local all, errors = {}, {}
  for name, finder in pairs(only or finders) do
    local ok, result = pcall(finder, ctx)
    if ok then
      for _, o in ipairs(result) do all[#all + 1] = o end
    else
      errors[#errors + 1] = name .. ": " .. tostring(result)
    end
  end
  table.sort(all, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.itemID < b.itemID
  end)
  return all, errors
end
