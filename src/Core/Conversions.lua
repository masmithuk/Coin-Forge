-- Conversions: item transformations that need no profession (e.g. essences).
local _, ns = ...

local Conversions = {}
ns.Conversions = Conversions

function Conversions.all()
  return ns.Data.Conversions
end

function Conversions.byKey(key)
  for _, c in ipairs(ns.Data.Conversions) do
    if c.key == key then return c end
  end
  return nil
end

local function total(parts, priceOf)
  local sum = 0
  for _, part in ipairs(parts) do
    local price = priceOf(part[1])
    if not price then return nil end
    sum = sum + price * part[2]
  end
  return sum
end

--- @param buyPrice function(itemID) -> copper per input unit
--- @param sellValue function(itemID) -> net copper per output unit
--- @return { cost, revenue, profit } or nil if a price is missing
function Conversions.evaluate(conv, buyPrice, sellValue)
  local cost = total(conv.inputs, buyPrice)
  local revenue = total(conv.outputs, sellValue)
  if not cost or not revenue then return nil end
  return { cost = cost, revenue = revenue, profit = revenue - cost }
end
