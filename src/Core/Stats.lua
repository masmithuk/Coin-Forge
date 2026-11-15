-- Stats: small statistics helpers used by the price model.
local _, ns = ...

local Stats = {}
ns.Stats = Stats

local function sortedCopy(list)
  local copy = {}
  for i = 1, #list do copy[i] = list[i] end
  table.sort(copy)
  return copy
end

function Stats.median(list)
  local n = #list
  if n == 0 then return nil end
  local s = sortedCopy(list)
  if n % 2 == 1 then return s[(n + 1) / 2] end
  return (s[n / 2] + s[n / 2 + 1]) / 2
end

function Stats.mean(list)
  if #list == 0 then return nil end
  local sum = 0
  for _, v in ipairs(list) do sum = sum + v end
  return sum / #list
end

--- Price of the unit sitting at percentile p (0..1) when every listed unit is
-- lined up cheapest first. entries = { {price=, count=}, ... } in any order.
function Stats.weightedPercentile(entries, p)
  if #entries == 0 then return nil end
  local sorted = {}
  local total = 0
  for i, e in ipairs(entries) do
    sorted[i] = e
    total = total + e.count
  end
  table.sort(sorted, function(a, b) return a.price < b.price end)
  local target = p * total
  local cumulative = 0
  for _, e in ipairs(sorted) do
    cumulative = cumulative + e.count
    if cumulative >= target then return e.price end
  end
  return sorted[#sorted].price
end
