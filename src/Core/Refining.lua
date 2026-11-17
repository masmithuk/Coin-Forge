-- Refining: is an item worth more turned into something else first?
--
-- Covers every single-ingredient recipe your characters have learned
-- (Tin Ore -> Tin Bar, 2 Linen Cloth -> Heavy Linen Bandage, ...) and the
-- essence conversions anyone can do. Each option is valued per item you start
-- with, after the AH cut, and compared with selling the item as it is.
local _, ns = ...

local Refining = {}
ns.Refining = Refining

--- @param recipes recipe list (see Crafting.lua), with knownByPlayer and crafters
--- @param conversions conversion list (see Data/Conversions.lua)
--- @return options { name, profession, outputItemID, inQty, outQty, knownByPlayer, crafters }
function Refining.optionsFor(itemID, recipes, conversions)
  local options = {}
  for _, r in ipairs(recipes or {}) do
    local only = #r.reagents == 1 and r.reagents[1]
    if only and only.itemID == itemID and r.outputItemID then
      options[#options + 1] = {
        name = r.name, profession = r.profession, outputItemID = r.outputItemID,
        inQty = only.qty, outQty = r.outputQty or 1,
        knownByPlayer = r.knownByPlayer == true, crafters = r.crafters,
      }
    end
  end
  for _, c in ipairs(conversions or {}) do
    if #c.inputs == 1 and #c.outputs == 1 and c.inputs[1][1] == itemID then
      options[#options + 1] = {
        name = c.name, outputItemID = c.outputs[1][1], inQty = c.inputs[1][2], outQty = c.outputs[1][2],
        knownByPlayer = true, -- no profession needed
      }
    end
  end
  return options
end

--- Values the options for one item.
--- @param ctx { price(itemID) -> gross copper or nil, net(gross) -> copper after the AH cut }
--- @return { asIs (net value of one item as it is, or nil),
---           options = sorted best first, each with valueEach (net value per item
---           you start with, or nil if the output has no price) and gain (vs asIs) }
function Refining.evaluate(itemID, options, ctx)
  local own = ctx.price(itemID)
  local asIs = own and ctx.net(own) or nil
  local valued = {}
  for i, o in ipairs(options) do
    local v = {}
    for k, x in pairs(o) do v[k] = x end
    local out = ctx.price(o.outputItemID)
    if out then
      v.valueEach = math.floor(ctx.net(out) * o.outQty / o.inQty)
      if asIs then v.gain = v.valueEach - asIs end
    end
    valued[i] = v
  end
  table.sort(valued, function(a, b)
    if a.valueEach and b.valueEach then return a.valueEach > b.valueEach end
    if a.valueEach or b.valueEach then return a.valueEach ~= nil end
    return (a.name or "") < (b.name or "")
  end)
  return { asIs = asIs, options = valued }
end
