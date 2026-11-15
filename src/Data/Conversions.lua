-- Item conversions anyone can do (no profession), e.g. combining essences.
--
-- Each pair below produces two conversions: 3 lesser -> 1 greater ("combine")
-- and 1 greater -> 3 lesser ("split"). Add other conversions to `extra`
-- using the same shape: { key, name, inputs = {{itemID, qty}}, outputs = {{itemID, qty}} }.
local _, ns = ...

local essencePairs = {
  { lesser = 10938, greater = 10939, name = "Magic Essence" },
  { lesser = 10998, greater = 11082, name = "Astral Essence" },
  { lesser = 11134, greater = 11135, name = "Mystic Essence" },
  { lesser = 11174, greater = 11175, name = "Nether Essence" },
  { lesser = 16202, greater = 16203, name = "Eternal Essence" },
}

local list = {}
for _, p in ipairs(essencePairs) do
  list[#list + 1] = {
    key = "combine:" .. p.lesser,
    name = "Combine Lesser " .. p.name,
    inputs = { { p.lesser, 3 } },
    outputs = { { p.greater, 1 } },
  }
  list[#list + 1] = {
    key = "split:" .. p.greater,
    name = "Split Greater " .. p.name,
    inputs = { { p.greater, 1 } },
    outputs = { { p.lesser, 3 } },
  }
end

ns.Data.Conversions = list
