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
  return { cost = math.floor(cost), revenue = math.floor(revenue), profit = math.floor(revenue - cost) }
end

--- Every conversion with its current profit or loss (for the Conversions view),
--- most profitable first; ones missing a price come last with profit = nil.
--- @return { {conversion, cost, revenue, profit}, ... }
function Conversions.evaluateAll(list, buyPrice, sellValue)
  local rows = {}
  for _, conv in ipairs(list) do
    local r = Conversions.evaluate(conv, buyPrice, sellValue) or {}
    r.conversion = conv
    rows[#rows + 1] = r
  end
  table.sort(rows, function(a, b)
    if a.profit and b.profit then return a.profit > b.profit end
    if a.profit or b.profit then return a.profit ~= nil end
    return a.conversion.key < b.conversion.key
  end)
  return rows
end
