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

  describe("selling", function()
    before_each(function()
      _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
      _G.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
        GetContainerItemInfo = function(_, slot)
          return ({ { itemID = 4306, stackCount = 20, hyperlink = "item:4306" },
                    { itemID = 4305, stackCount = 2, hyperlink = "item:4305" } })[slot]
        end,
      }
      _G.Enum.ItemCommodityStatus = { Item = 1, Commodity = 2 }
      local ah = _G.C_AuctionHouse
      ah.IsSellItemValid = function() return true end
      ah.GetItemCommodityStatus = function() return 2 end
      ah.GetAvailablePostCount = function(loc) return loc.slot == 1 and 20 or 2 end
    end)

    after_each(function() _G.ItemLocation, _G.C_Container = nil, nil end)

    it("lists bag items with a suggested price, most valuable first", function()
      for day = 1, 2 do
        now = (50 + day) * 86400
        scan({ { itemID = 4306, count = 10, buyout = 10 * 100 }, { itemID = 4305, count = 1, buyout = 2000 } })
      end
      local rows = app:sellRows()
      assert.equal(2, #rows)
      -- sorted by total value: 2 bolts x 1999c (3998c) before 20 silk x 99c (1980c)
      assert.equal(4305, rows[1].item.itemID)
      assert.equal(1999, rows[1].suggestion.price)
      assert.equal(3998, rows[1].total)
      assert.equal(99, rows[2].suggestion.price)
    end)

    it("folds live search results into the price data and the current deals", function()
      local updated = 0
      app.events:on("pricesUpdated", function() updated = updated + 1 end)
      scan({ { itemID = 4306, count = 10, buyout = 10 * 100 } })
      app.sellSearch.onListings(4306, { { price = 60, count = 2, mine = false }, { price = 100, count = 9 } })
      local info = app.prices:getInfo("Forever|Horde", 4306)
      assert.equal(60, info.low)
      assert.equal(11, info.qty)
      assert.equal(60, app.scanner.lastResult.listings[4306][1].price)
      assert.equal(1, updated)
    end)

    it("refines the suggestion with live prices and announces it", function()
      local got
      app.events:on("sellSuggestion", function(item, suggestion, live) got = { item, suggestion, live } end)
      for day = 1, 2 do
        now = (50 + day) * 86400
        scan({ { itemID = 4306, count = 10, buyout = 10 * 100 } })
      end
      local item = app:sellRows()[1].item
      app.sellSearch.onResults(item, { { price = 95, count = 3, mine = false } })
      assert.equal(94, got[2].price)
      assert.is_true(got[3])
    end)
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
