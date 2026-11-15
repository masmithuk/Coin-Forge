-- Settings: user-tunable thresholds with defaults and typed setters.
local _, ns = ...

local Settings = {}
ns.Settings = Settings

-- Each setting: default value and the kind of value it holds.
--   money  : copper amount, accepts "1g 50s"
--   number : plain number
--   ratio  : 0..1, accepts "30%" or "0.3"
--   bool   : on/off
local schema = {
  minProfit       = { default = 5000,  kind = "money",  help = "Minimum total profit for an opportunity" },
  flipDiscount    = { default = 0.30,  kind = "ratio",  help = "How far under market value a listing must be to flip" },
  minHistoryDays  = { default = 2,     kind = "number", help = "Days of price history needed before trusting a value" },
  mobMinValue     = { default = 5000,  kind = "money",  help = "Expected loot value per kill to highlight a mob" },
  mobMinKills     = { default = 5,     kind = "number", help = "Kills recorded before a mob's value is trusted" },
  historyDays     = { default = 30,    kind = "number", help = "Days of price snapshots to keep" },
  showNameplates  = { default = true,  kind = "bool",   help = "Mark profitable mobs on nameplates" },
  showTooltips    = { default = true,  kind = "bool",   help = "Add prices to item and unit tooltips" },
  showMerchant    = { default = true,  kind = "bool",   help = "Highlight vendor items worth more on the AH" },
  showMinimap     = { default = true,  kind = "bool",   help = "Show the minimap button" },
}

Settings.schema = schema
Settings.defaults = {}
for key, def in pairs(schema) do Settings.defaults[key] = def.default end

--- Fills any missing settings with defaults. Mutates and returns `saved`.
function Settings.apply(saved)
  saved = saved or {}
  for key, value in pairs(Settings.defaults) do
    if saved[key] == nil then saved[key] = value end
  end
  return saved
end

local converters = {
  money = function(text) return ns.Money.parse(text) end,
  number = function(text) return tonumber(text) end,
  ratio = function(text)
    local pct = tostring(text):match("^%s*([%d%.]+)%s*%%%s*$")
    if pct then return tonumber(pct) / 100 end
    local n = tonumber(text)
    if n and n > 1 then return n / 100 end
    return n
  end,
  bool = function(text)
    text = tostring(text):lower()
    if text == "on" or text == "true" or text == "1" or text == "yes" then return true end
    if text == "off" or text == "false" or text == "0" or text == "no" then return false end
    return nil
  end,
}

--- Sets `key` from user text. Returns true, or false plus an error message.
function Settings.set(settings, key, text)
  local def = schema[key]
  if not def then return false, "unknown setting '" .. tostring(key) .. "'" end
  local value = converters[def.kind](text)
  if value == nil then return false, "invalid value for " .. key .. " (" .. def.kind .. ")" end
  settings[key] = value
  return true
end
