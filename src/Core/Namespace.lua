-- Namespace: shared tables every module hangs off.
--
-- WoW gives each addon file (addonName, ns). Modules register themselves as
-- ns.<ModuleName>; static data goes under ns.Data.
local addonName, ns = ...

ns.name = addonName
ns.Data = ns.Data or {}
ns.version = "0.7.3"

--- True for values the game hides from addons (for example unit names and
--- GUIDs inside instances on newer clients). They can be passed along but not
--- compared, matched or used as table keys, so callers skip them.
function ns.isSecret(value)
  local check = _G.issecretvalue
  return check ~= nil and check(value) == true
end
