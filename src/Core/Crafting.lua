-- Crafting: cost, revenue and profit of recipes.
--
-- A recipe is a plain table (recorded by WoW/TradeSkillRecorder):
--   { key, name, profession, outputItemID, outputQty, reagents = {{itemID, qty}},
--     crafters = {"Name-Realm", ...}, knownByPlayer = bool }
--
-- Pricing comes from a context so callers decide which prices to use
-- ("buy now" from current listings, or long-run market values):
--   ctx.buyPrice(itemID)  -> copper to buy one on the AH, or nil
--   ctx.vendorBuy(itemID) -> copper to buy one from a vendor, or nil
--   ctx.sellValue(itemID) -> net copper received selling one, or nil
local _, ns = ...

local Crafting = {}
ns.Crafting = Crafting

--- Cheapest known source for one reagent.
function Crafting.reagentCost(itemID, ctx)
  local ah = ctx.buyPrice(itemID)
  local vendor = ctx.vendorBuy and ctx.vendorBuy(itemID)
  if ah and vendor then return math.min(ah, vendor) end
  return ah or vendor
end

--- @return { recipe, cost, revenue, profit, margin, missing = {itemIDs} }
-- cost/profit/margin are nil if any reagent has no known price.
function Crafting.evaluate(recipe, ctx)
  local cost, missing = 0, {}
  for _, r in ipairs(recipe.reagents) do
    local unit = Crafting.reagentCost(r.itemID, ctx)
    if unit then
      cost = cost + unit * r.qty
    else
      missing[#missing + 1] = r.itemID
    end
  end

  local unitValue = ctx.sellValue(recipe.outputItemID)
  local revenue = unitValue and math.floor(unitValue * (recipe.outputQty or 1)) or nil
  local result = { recipe = recipe, revenue = revenue, missing = missing }
  if #missing == 0 then
    result.cost = cost
    if revenue then
      result.profit = revenue - cost
      result.margin = cost > 0 and result.profit / cost or nil
    end
  end
  return result
end

--- Evaluates many recipes, most profitable first; unknown profit last.
function Crafting.evaluateAll(recipes, ctx)
  local list = {}
  for _, recipe in ipairs(recipes) do list[#list + 1] = Crafting.evaluate(recipe, ctx) end
  table.sort(list, function(a, b)
    if a.profit and b.profit then return a.profit > b.profit end
    if a.profit then return true end
    if b.profit then return false end
    return (a.recipe.name or "") < (b.recipe.name or "")
  end)
  return list
end
