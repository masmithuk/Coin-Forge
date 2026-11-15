-- Integration tests: the App wiring with a fake client.
local addon = require("helpers.addon")
local wow = require("helpers.wow_mock")

local function appFiles()
  local files = {}
  for _, f in ipairs(addon.tocFiles("src/WoW/")) do files[#files + 1] = f end
  return files
end

describe("App", function()
  local ns, app, now, replicate, items, saved

  before_each(function()
    now = 50 * 86400
    replicate = {}
    items = {
      [4306] = { "Silk Cloth", nil, 1, 30, 0, "Trade", "Cloth", 20, "", 1, 150, 7 },
      [4305] = { "Bolt of Silk Cloth", nil, 1, 30, 0, "Trade", "Cloth", 20, "", 1, 400, 7 },
    }
    wow.install({
      time = function() return now end,
      GetItemInfo = function(id) if items[id] then return unpack(items[id]) end end,
      C_AuctionHouse = {
        ReplicateItems = function() end,
        GetNumReplicateItems = function() return #replicate end,
        GetReplicateItemInfo = function(i)
          local r = replicate[i + 1]
          return nil, nil, r.count, 1, true, 1, "", 0, 0, r.buyout, 0, false, nil, nil, nil, 0, r.itemID, true
        end,
      },
      GetNumSkillLines = function() return 1 end,
      GetSkillLineInfo = function() return "Tailoring", false, false, 150 end,
    })
    ns = addon.loadWith(appFiles())
    saved = {}
    app = ns.App.new(saved, function() return now end)
  end)

  after_each(function() wow.uninstall() end)

  local function scan(listings)
    replicate = listings
    app.scanner.state.lastStart = nil
    assert.is_true((app:startScan()))
    app.scanner:onEvent("REPLICATE_ITEM_LIST_UPDATE")
  end

  it("creates its saved structures with default settings", function()
    assert.is_table(saved.markets)
    assert.is_table(saved.mobs)
    assert.equal(ns.Settings.defaults.minProfit, app.settings.minProfit)
  end)

  it("finds a flip after enough days of history", function()
    for day = 1, 3 do
      now = (50 + day) * 86400
      scan({ { itemID = 4306, count = 20, buyout = 20 * 1000 } })
    end
    now = now + 86400
    scan({ { itemID = 4306, count = 10, buyout = 10 * 200 }, { itemID = 4306, count = 20, buyout = 20 * 1000 } })
    local deals = app.lastOpportunities
    assert.is_true(#deals >= 1)
    assert.equal("flip", deals[1].kind)
    assert.equal(4306, deals[1].itemID)
    assert.is_table(saved.lastDeals)
  end)

  it("values crafts from recorded recipes", function()
    saved.recipes = { ["Tailoring:4305"] = {
      key = "Tailoring:4305", name = "Bolt of Silk Cloth", profession = "Tailoring", outputItemID = 4305,
      outputQty = 1, reagents = { { itemID = 4306, qty = 4 } }, crafters = { [app.charKey] = true },
    } }
    for day = 1, 2 do
      now = (50 + day) * 86400
      scan({ { itemID = 4306, count = 1, buyout = 100 }, { itemID = 4305, count = 1, buyout = 1000 } })
    end
    local rows = app:craftRows()
    assert.equal(1, #rows)
    assert.equal(400, rows[1].cost)
    assert.equal(950, rows[1].revenue)
    assert.equal(550, rows[1].profit)
  end)

  it("values mobs from loot using the best action for each drop", function()
    for day = 1, 2 do
      now = (50 + day) * 86400
      scan({ { itemID = 4306, count = 1, buyout = 1000 } })
    end
    app.loot:record(77, "g1", { { itemID = 4306, qty = 2 } }, 100)
    local ev, kills = app:mobValue(77)
    assert.equal(1, kills)
    assert.equal(100 + 2 * 950, ev)
  end)

  it("finds vendor snipes for items whose data loads after the scan", function()
    items[4306] = nil -- not cached by the client yet
    local requested = {}
    _G.C_Item = { RequestLoadItemDataByID = function(id) requested[id] = true end }
    app.settings.minProfit = 1
    scan({ { itemID = 4306, count = 10, buyout = 10 * 5 } }) -- 5c each, vendor pays 150c
    assert.is_true(requested[4306])
    assert.same({}, app.lastOpportunities)

    items[4306] = { "Silk Cloth", nil, 1, 30, 0, "Trade", "Cloth", 20, "", 1, 150, 7 }
    app:onItemInfoReceived()
    assert.equal("vendor", app.lastOpportunities[1].kind)
    assert.equal(1450, app.lastOpportunities[1].profit)
    _G.C_Item = nil
  end)

  it("records vendor stock with where to buy it", function()
    _G.GetMerchantNumItems = function() return 1 end
    _G.GetMerchantItemInfo = function() return "Silk", 1, 300, 5, 3, true, true, false end
    _G.GetMerchantItemID = function() return 4306 end
    _G.UnitName = function(unit) return unit == "npc" and "Bob" or "Thrall" end
    _G.GetZoneText = function() return "Ironforge" end
    app:merchantDeals()
    assert.same({ price = 60, stack = 5, available = 3, merchant = "Bob", zone = "Ironforge" },
      saved.vendorItems[4306])
    assert.equal(60, saved.vendorPrices[4306])
  end)

  it("lists every essence conversion with live prices", function()
    for day = 1, 2 do
      now = (50 + day) * 86400
      scan({ { itemID = 10938, count = 10, buyout = 10 * 100 }, { itemID = 10939, count = 2, buyout = 2 * 1000 } })
    end
    local rows = app:conversionRows()
    assert.equal(#ns.Conversions.all(), #rows)
    assert.equal("combine:10938", rows[1].conversion.key)
    assert.equal(300, rows[1].cost)
    assert.equal(950, rows[1].revenue)
    assert.equal(650, rows[1].profit)
  end)

  it("reports home screen state", function()
    local s = app:homeState()
    assert.is_false(s.scanned)
    assert.equal(0, s.mobsLearned)
  end)

  it("tracks looted item value in the session", function()
    for day = 1, 2 do
      now = (50 + day) * 86400
      scan({ { itemID = 4306, count = 1, buyout = 1000 } })
    end
    app:onItemsLooted({ { itemID = 4306, qty = 3 } })
    assert.equal(3 * 950, app.session:summary(0).loot)
  end)
end)
