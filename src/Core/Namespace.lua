-- Namespace: shared tables every module hangs off.
--
-- WoW gives each addon file (addonName, ns). Modules register themselves as
-- ns.<ModuleName>; static data goes under ns.Data.
local addonName, ns = ...

ns.name = addonName
ns.Data = ns.Data or {}
ns.version = "0.1.0"
