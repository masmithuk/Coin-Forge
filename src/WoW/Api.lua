-- Api: small helpers around the WoW client API.
--
-- WoW Forever runs on the modern client but is brand new, so every adapter
-- checks an API exists before using it (Api.has) and degrades gracefully.
local _, ns = ...

local Api = {}
ns.Api = Api

--- True if a dotted global path like "C_AuctionHouse.ReplicateItems" exists.
function Api.has(path)
  local node = _G
  for part in path:gmatch("[^%.]+") do
    if type(node) ~= "table" then return false end
    node = node[part]
    if node == nil then return false end
  end
  return true
end

function Api.itemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

--- Prints a message to the chat frame with the addon prefix.
function Api.print(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100ForeverGold|r: " .. tostring(message))
  end
end

--- "Name-Realm" for the current character.
function Api.characterKey()
  local name, realm = UnitFullName("player")
  return (name or "?") .. "-" .. (realm or GetRealmName() or "?")
end
