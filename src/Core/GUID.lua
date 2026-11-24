-- GUID: helpers for unit GUID strings.
-- Creature GUIDs look like "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>".
local _, ns = ...

local GUID = {}
ns.GUID = GUID

local NPC_TYPES = { Creature = true, Vehicle = true }

function GUID.npcID(guid)
  if type(guid) ~= "string" or ns.isSecret(guid) then return nil end
  local unitType, npcID = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if not NPC_TYPES[unitType] then return nil end
  return tonumber(npcID)
end

--- True for world objects such as mining veins, herbs and chests.
function GUID.isObject(guid)
  return type(guid) == "string" and not ns.isSecret(guid) and guid:match("^GameObject%-") ~= nil
end
