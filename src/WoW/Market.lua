-- Market: which auction house you're standing at.
--
-- WoW Forever is realmless (one mega-realm per ruleset), but faction AHs are
-- still separate from the neutral goblin AH, which has a 15% cut.
local _, ns = ...

local Market = {}
ns.Market = Market

-- enUS/enGB names of the towns with a neutral auction house.
Market.NEUTRAL_TOWNS = { ["Booty Bay"] = true, ["Gadgetzan"] = true, ["Everlook"] = true }

local NEUTRAL = "Neutral"

function Market.key(realm, faction, subzone)
  local side = Market.NEUTRAL_TOWNS[subzone or ""] and NEUTRAL or (faction or "?")
  return (realm or "?") .. "|" .. side
end

function Market.isNeutralKey(key)
  return key:match("|(.+)$") == NEUTRAL
end

function Market.realmOf(key)
  return key:match("^(.-)|")
end

function Market.label(key)
  return (key:match("|(.+)$") or "?") .. " AH"
end

--- @return key, isNeutral, label for where the player is now
function Market.current()
  local subzone = GetSubZoneText and GetSubZoneText() or ""
  if not Market.NEUTRAL_TOWNS[subzone] and GetZoneText then
    local zone = GetZoneText()
    if Market.NEUTRAL_TOWNS[zone] then subzone = zone end
  end
  local key = Market.key(GetRealmName(), UnitFactionGroup("player"), subzone)
  return key, Market.isNeutralKey(key), Market.label(key)
end
