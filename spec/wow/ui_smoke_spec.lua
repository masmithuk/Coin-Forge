-- Smoke tests: boot the whole addon in the fake client and drive every screen.
-- These catch runtime errors in UI code (nil calls, typos) that unit tests can't.
local addon = require("helpers.addon")
local wow = require("helpers.wow_mock")

describe("UI smoke test", function()
  local env, ns, eventFrame, now, replicate

  local function fire(event, ...)
    eventFrame:Fire("OnEvent", event, ...)
  end

  before_each(function()
    now = 100 * 86400
    replicate = {
      { itemID = 4306, count = 20, buyout = 20 * 100 },
      { itemID = 4306, count = 5, buyout = 5 * 10 },
    }
    env = wow.install({
      time = function() return now end,
      GetMoney = function() return 12345 end,
      GetItemInfo = function(id) return "Item " .. id, nil, 1, 30, 0, "", "", 20, "", 1, 50, 7 end,
      C_AuctionHouse = {
        ReplicateItems = function() end,
        GetNumReplicateItems = function() return #replicate end,
        GetReplicateItemInfo = function(i)
          local r = replicate[i + 1]
          return nil, nil, r.count, 1, true, 1, "", 0, 0, r.buyout, 0, false, nil, nil, nil, 0, r.itemID, true
        end,
      },
      MERCHANT_ITEMS_PER_PAGE = 10,
      GetMerchantNumItems = function() return 1 end,
      GetMerchantItemInfo = function() return "Thing", 1, 10, 1, -1, true, true, false end,
      GetMerchantItemID = function() return 4306 end,
      GetCursorPosition = function() return 0, 0 end,
      UISpecialFrames = {},
    })
    env.AuctionHouseFrame = wow.frame(env.UIParent, "AuctionHouseFrame")
    env.AuctionHouseFrame.SearchBar = wow.frame(env.AuctionHouseFrame)
    env.AuctionHouseFrame.SearchBar.SearchBox = wow.frame(env.AuctionHouseFrame.SearchBar)
    env.MerchantFrame = wow.frame(env.UIParent, "MerchantFrame")
    env.MerchantFrame.shown = true
    env.MerchantFrame.page = 1
    env.MerchantFrame.selectedTab = 1
    for i = 1, 10 do _G["MerchantItem" .. i .. "ItemButton"] = wow.frame(env.MerchantFrame) end
    _G.AuctionHouseFrame, _G.MerchantFrame = env.AuctionHouseFrame, env.MerchantFrame
    _G.ForeverGoldDB = nil

    ns = addon.load(addon.tocFiles())
    eventFrame = env.__created[1]
    fire("ADDON_LOADED", "ForeverGold")
  end)

  after_each(function()
    for i = 1, 10 do _G["MerchantItem" .. i .. "ItemButton"] = nil end
    _G.ForeverGoldDB = nil
    wow.uninstall()
  end)

  it("boots, registers the slash command and the minimap button", function()
    assert.is_table(ns.app)
    assert.is_function(_G.SlashCmdList.FOREVERGOLD)
    assert.is_not_nil(_G.ForeverGoldMinimapButton)
    assert.is_function(_G.ForeverGold_OnCompartmentClick)
  end)

  it("still boots on a client that rejects event names it doesn't know (WoW Forever)", function()
    wow.uninstall()
    -- Events the Forever (retail-based) client knows; classic-only TRADE_SKILL_UPDATE is missing.
    local valid = {}
    for _, e in ipairs({ "ADDON_LOADED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
      "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
      "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "MERCHANT_SHOW", "MERCHANT_UPDATE", "TRADE_SKILL_SHOW",
      "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do valid[e] = true end
    wow.validEvents = valid
    local fresh = wow.install({ C_EventUtils = { IsEventValid = function(e) return valid[e] == true end } })
    local ok, err = pcall(function()
      local freshNs = addon.load(addon.tocFiles())
      fresh.__created[1]:Fire("OnEvent", "ADDON_LOADED", "ForeverGold")
      assert.is_table(freshNs.app)
    end)
    wow.validEvents = nil
    assert.is_true(ok, tostring(err))
    assert.is_not_nil(_G.ForeverGoldMinimapButton)
  end)

  it("opens the home screen from the slash command and minimap", function()
    _G.SlashCmdList.FOREVERGOLD("")
    assert.is_true(_G.ForeverGoldHome.shown)
    _G.ForeverGoldMinimapButton:Fire("OnClick")
    assert.is_false(_G.ForeverGoldHome.shown)
    _G.ForeverGoldMinimapButton:Fire("OnEnter")
  end)

  it("shows the auction panel, scans across days and lists deals", function()
    fire("AUCTION_HOUSE_SHOW")
    local panel = _G.ForeverGoldAuctionPanel
    assert.is_true(panel.shown)
    for day = 1, 3 do
      now = (100 + day) * 86400
      ns.app.scanner.state.lastStart = nil
      replicate = { { itemID = 4306, count = 20, buyout = 20 * 100 } }
      ns.app:startScan()
      fire("REPLICATE_ITEM_LIST_UPDATE")
    end
    now = now + 86400
    ns.app.scanner.state.lastStart = nil
    replicate = { { itemID = 4306, count = 200, buyout = 200 * 10 }, { itemID = 4306, count = 20, buyout = 2000 } }
    ns.app.settings.minProfit = 1
    ns.app:startScan()
    fire("REPLICATE_ITEM_LIST_UPDATE")
    assert.is_true(#ns.app.lastOpportunities > 0)

    -- switch views, resize, click and hover a row
    local p = ns.app and ns.AuctionPanel
    assert.is_table(p)
    panel:SetSize(320, 300)
    panel:Fire("OnSizeChanged")
    _G.SlashCmdList.FOREVERGOLD("config minProfit 2s")
    assert.equal(200, ns.app.settings.minProfit)
  end)

  it("drives deal rows, crafting view and filters without errors", function()
    fire("AUCTION_HOUSE_SHOW")
    local panelObj
    -- find the panel object through a scan event round trip
    ns.app.lastOpportunities = {
      { kind = "flip", itemID = 4306, qty = 5, maxPrice = 10, cost = 50, revenue = 475, profit = 425,
        canDo = true, note = "Relist" },
      { kind = "craft", itemID = 4305, qty = 1, cost = 50, revenue = 475, profit = 300,
        canDo = false, note = "Known by Alt" },
    }
    ns.app.events:emit("opportunitiesUpdated", ns.app.lastOpportunities)
    for _, f in ipairs(env.__created) do
      if f.item and f.scripts.OnClick then panelObj = f break end
    end
    assert.is_not_nil(panelObj, "expected a populated deal row")
    panelObj:Fire("OnEnter")
    panelObj:Fire("OnClick", "LeftButton")
    assert.equal("Item 4306", env.AuctionHouseFrame.SearchBar.SearchBox.text)
    panelObj:Fire("OnLeave")

    local function clickTab(kind)
      for _, f in ipairs(env.__created) do
        if f.kind == kind and f.scripts.OnClick then f:Fire("OnClick") return true end
      end
      return false
    end
    -- kind filter tab, then the Crafting view with a recorded recipe, then back
    assert.is_true(clickTab("craft"))
    ns.app.db.recipes["Tailoring:4305"] = {
      key = "Tailoring:4305", name = "Bolt", profession = "Tailoring", outputItemID = 4305, outputQty = 1,
      reagents = { { itemID = 4306, qty = 4 } }, crafters = { Alt = true },
    }
    assert.is_true(clickTab("crafting"))
    assert.is_true(clickTab("conversions"))
    assert.is_true(clickTab("split"))
    local convList
    for _, f in ipairs(env.__created) do
      if f.header and f.items and f.items[1] and f.items[1].conversion then convList = f end
    end
    assert.is_not_nil(convList, "expected the conversions list")
    for _, item in ipairs(convList.items) do assert.matches("^split:", item.conversion.key) end
    assert.is_true(clickTab("deals"))
    fire("GET_ITEM_INFO_RECEIVED", 4306)
    -- the "only what I can do" toggle really removes the deal this character can't do
    local dealList
    for _, f in ipairs(env.__created) do
      for _, item in ipairs(f.header and f.items or {}) do
        if item.canDo == false then dealList = f end
      end
    end
    assert.is_not_nil(dealList, "expected the deals list to show the deal this character can't do")
    for _, f in ipairs(env.__created) do
      if f.scripts.OnClick and f.checked ~= nil then f.checked = true; f:Fire("OnClick") end
    end
    assert.is_true(#dealList.items >= 1)
    for _, item in ipairs(dealList.items) do assert.is_true(item.canDo) end
  end)

  it("highlights profitable merchant items", function()
    replicate = { { itemID = 4306, count = 20, buyout = 20 * 100 } }
    for day = 1, 3 do
      now = (100 + day) * 86400
      ns.app.scanner.state.lastStart = nil
      ns.app:startScan()
      fire("REPLICATE_ITEM_LIST_UPDATE")
    end
    fire("MERCHANT_SHOW")
    local deals = ns.app:merchantDeals()
    assert.equal(1, #deals)
    assert.equal(4306, deals[1].itemID)
  end)

  it("records loot and marks profitable nameplates", function()
    local plate = wow.frame(nil, "Plate")
    _G.C_NamePlate = { GetNamePlateForUnit = function() return plate end }
    _G.UnitGUID = function() return "Creature-0-1-0-1-777-ABC" end
    _G.GetNumLootItems = function() return 1 end
    _G.GetLootSlotType = function() return 2 end
    _G.GetLootSourceInfo = function() return "Creature-0-1-0-1-777-ABC", 100000 end
    ns.app.settings.mobMinKills = 1
    fire("LOOT_OPENED")
    fire("LOOT_SLOT_CLEARED", 1)
    fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    assert.is_true(plate.ForeverGoldMarker.shown)
    fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
  end)

  it("renders the home screen with data and on resize", function()
    ns.app.loot:record(5, "g", {}, 50000)
    ns.app.settings.mobMinKills = 1
    ns.app.db.lastDeals = { { kind = "flip", itemID = 4306, profit = 500 } }
    _G.SlashCmdList.FOREVERGOLD("")
    local home = _G.ForeverGoldHome
    home:SetSize(320, 400)
    home:Fire("OnSizeChanged")
    _G.SlashCmdList.FOREVERGOLD("mobs")
    _G.SlashCmdList.FOREVERGOLD("help")
    _G.SlashCmdList.FOREVERGOLD("config")
    _G.SlashCmdList.FOREVERGOLD("reset")
    _G.SlashCmdList.FOREVERGOLD("minimap")
    assert.is_false(ns.app.settings.showMinimap)
  end)
end)
