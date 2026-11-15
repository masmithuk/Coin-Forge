-- Main: entry point. Creates the App once saved variables load, connects game
-- events to the services, and registers the /fg command.
local addonName, ns = ...

local events = CreateFrame("Frame")
local handlers = {}
local app, home, minimap, panel, merchant, nameplates, lootRecorder

-- Registers a handler for a game event. Events differ between game versions,
-- and the retail-based Forever client raises an error for unknown names, which
-- would stop this file loading. So only register events the client knows.
local function on(event, fn)
  local isValid = _G.C_EventUtils and _G.C_EventUtils.IsEventValid
  if isValid and not isValid(event) then return end
  if pcall(events.RegisterEvent, events, event) then handlers[event] = fn end
end

-- Runs fn at most once per `delay` seconds, after events stop arriving.
local function debounce(delay, fn)
  local pending = false
  return function()
    if pending then return end
    pending = true
    C_Timer.After(delay, function()
      pending = false
      fn()
    end)
  end
end

local function learnName(unit)
  local npcID = ns.GUID.npcID(UnitGUID(unit))
  if npcID then app.loot:setName(npcID, UnitName(unit)) end
end

local function printHelp()
  local p = ns.Api.print
  p("commands:")
  p("  /fg - open or close the home screen")
  p("  /fg mobs - list the best mobs you've farmed")
  p("  /fg reset - start a new farming session")
  p("  /fg minimap - show or hide the minimap button")
  p("  /fg config - list settings, /fg config <name> <value> to change one")
end

local function printConfig(args)
  local p = ns.Api.print
  if #args == 0 then
    local keys = {}
    for key in pairs(ns.Settings.schema) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local def, value = ns.Settings.schema[key], app.settings[key]
      local shown = def.kind == "money" and ns.Money.format(value)
        or def.kind == "ratio" and (math.floor(value * 100 + 0.5) .. "%")
        or tostring(value)
      p(("  %s = %s  |cff8c8c99%s|r"):format(key, shown, def.help))
    end
    return
  end
  local ok, err = ns.Settings.set(app.settings, args[1], table.concat(args, " ", 2))
  p(ok and ("%s updated."):format(args[1]) or err)
  if ok then
    minimap:Apply()
    nameplates:refreshAll()
  end
end

local function printMobs()
  local mobs = app:topMobs(10)
  if #mobs == 0 then
    ns.Api.print(("No mob has %d+ kills recorded yet. Loot some mobs first."):format(app.settings.mobMinKills))
    return
  end
  for i, m in ipairs(mobs) do
    ns.Api.print(("%d. %s - %s per kill (%d kills)"):format(i, m.name or ("NPC " .. m.npcID),
      ns.Money.short(m.ev), m.kills))
  end
end

local function setupCommands()
  local router = ns.Commands.new({
    [""] = function() home:Toggle() end,
    help = printHelp,
    config = printConfig,
    mobs = printMobs,
    reset = function()
      app.session:reset(GetMoney())
      ns.Api.print("New session started.")
    end,
    minimap = function()
      app.settings.showMinimap = not app.settings.showMinimap
      minimap:Apply()
    end,
  })
  _G.SLASH_FOREVERGOLD1, _G.SLASH_FOREVERGOLD2 = "/fg", "/forevergold"
  SlashCmdList.FOREVERGOLD = function(text) router:run(text) end
end

local function setupAddonCompartment()
  _G.ForeverGold_OnCompartmentClick = function() home:Toggle() end
  _G.ForeverGold_OnCompartmentEnter = function(_, button)
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    ns.MinimapButton.fillTooltip(GameTooltip, app)
    GameTooltip:Show()
  end
  _G.ForeverGold_OnCompartmentLeave = function() GameTooltip:Hide() end
end

local function start()
  _G.ForeverGoldDB = _G.ForeverGoldDB or {}
  app = ns.App.new(_G.ForeverGoldDB, time)
  ns.app = app

  home = ns.HomeScreen.new(app)
  minimap = ns.MinimapButton.new(app, function() home:Toggle() end)
  minimap:Build()
  panel = ns.AuctionPanel.new(app)
  merchant = ns.MerchantOverlay.new(app)
  nameplates = ns.Nameplates.new({ settings = app.settings, valueOf = function(id) return app:mobValue(id) end })
  lootRecorder = ns.LootRecorder.new(app.loot, function(items) app:onItemsLooted(items) end)

  ns.Tooltip.install({
    settings = app.settings,
    item = {
      info = function(id) return app.prices:getInfo((app:market()), id) end,
      options = function(id) return app:appraisal():options(id) end,
      best = function(id) return app:appraisal():best(id) end,
    },
    unit = {
      expected = function(npcID) return app:mobValue(npcID) end,
      topDrops = function(npcID)
        return app.loot:topDrops(npcID, function(id) return app:valueOf(id) end, 3)
      end,
      nameOf = ns.ItemInfo.name,
    },
  })

  app.events:on("scanComplete", function(result)
    ns.Api.print(("Scan complete: %d items priced, %d deals found."):format(result.itemCount, #app.lastOpportunities))
    nameplates:refreshAll()
  end)

  setupCommands()
  setupAddonCompartment()

  if not app.db.ui.welcomed then
    app.db.ui.welcomed = true
    ns.Api.print("loaded. Click the coin on your minimap (or type /fg) to get started.")
  end
end

-- Game events ------------------------------------------------------------------

on("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  events:UnregisterEvent("ADDON_LOADED")
  start()
end)

on("AUCTION_HOUSE_SHOW", function() panel:Show(AuctionHouseFrame) end)
on("AUCTION_HOUSE_CLOSED", function() panel:Hide() end)
on("REPLICATE_ITEM_LIST_UPDATE", function() app.scanner:onEvent("REPLICATE_ITEM_LIST_UPDATE") end)

for _, e in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED" }) do
  on(e, function(...) lootRecorder:onEvent(e, ...) end)
end
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
  on(e, function(unit)
    if e == "NAME_PLATE_UNIT_ADDED" then learnName(unit) end
    nameplates:onEvent(e, unit)
  end)
end
on("PLAYER_TARGET_CHANGED", function() learnName("target") end)
on("UPDATE_MOUSEOVER_UNIT", function() learnName("mouseover") end)

local updateMerchant = debounce(0.1, function() merchant:Update() end)
on("MERCHANT_SHOW", function()
  updateMerchant()
  if _G.MerchantFrame_Update and not merchant.hooked then
    merchant.hooked = true
    hooksecurefunc("MerchantFrame_Update", updateMerchant)
  end
end)
on("MERCHANT_UPDATE", updateMerchant)

local recordRecipes = debounce(0.5, function() app:recordRecipes() end)
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE" }) do
  on(e, recordRecipes)
end
on("SKILL_LINES_CHANGED", function() app:refreshSkills() end)

-- Selling: live search results and bag changes.
for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }) do
  on(e, function(...) app.sellSearch:onEvent(e, ...) end)
end
on("BAG_UPDATE_DELAYED", debounce(0.3, function() panel:OnBagsChanged() end))

-- Item details arrive asynchronously after a scan. Once they settle, re-run the
-- finders (vendor and disenchant deals need them) and repaint the panel.
on("GET_ITEM_INFO_RECEIVED", debounce(1, function()
  app:onItemInfoReceived()
  panel:Refresh()
end))

events:SetScript("OnEvent", function(_, event, ...)
  local handler = handlers[event]
  if handler and (app or event == "ADDON_LOADED") then handler(...) end
end)
