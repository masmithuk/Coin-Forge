-- Money: formatting and parsing of copper amounts.
-- All prices inside the addon are integer copper (1g = 100s = 10000c).
local _, ns = ...

local Money = {}
ns.Money = Money

local GOLD, SILVER = 10000, 100

local function split(copper)
  copper = math.floor(math.abs(copper) + 0.5)
  local g = math.floor(copper / GOLD)
  local s = math.floor((copper % GOLD) / SILVER)
  local c = copper % SILVER
  return g, s, c
end

local function join(parts, negative)
  if #parts == 0 then parts[1] = "0c" end
  local text = table.concat(parts, " ")
  if negative and text ~= "0c" then text = "-" .. text end
  return text
end

--- "1g 23s 45c" style, omitting zero units.
function Money.format(copper)
  local g, s, c = split(copper)
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 then parts[#parts + 1] = c .. "c" end
  return join(parts, copper < 0)
end

--- Compact form for tight UI: copper is dropped once an amount reaches 1g.
function Money.short(copper)
  local g, s, c = split(copper)
  local parts = {}
  if g > 0 then
    parts[#parts + 1] = g .. "g"
    if s > 0 then parts[#parts + 1] = s .. "s" end
  else
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
  end
  return join(parts, copper < 0)
end

--- Parses "1g 2s 3c", "50s" or a plain copper number. Returns nil if invalid.
function Money.parse(text)
  text = tostring(text or ""):lower()
  local plain = tonumber(text)
  if plain then return math.floor(plain) end
  local total, matched = 0, false
  for amount, unit in text:gmatch("(%d+)%s*([gsc])") do
    matched = true
    local n = tonumber(amount)
    if unit == "g" then total = total + n * GOLD
    elseif unit == "s" then total = total + n * SILVER
    else total = total + n end
  end
  return matched and total or nil
end
