local addon = require("helpers.addon")
local wow = require("helpers.wow_mock")

local ADAPTERS = {
  "src/WoW/Api.lua", "src/WoW/ItemInfo.lua", "src/WoW/Market.lua", "src/WoW/Scanner.lua",
  "src/WoW/Professions.lua", "src/WoW/TradeSkillRecorder.lua", "src/WoW/LootRecorder.lua",
  "src/WoW/Nameplates.lua", "src/WoW/Merchant.lua", "src/WoW/Tooltip.lua",
}

local function link(id) return "|cff1eff00|Hitem:" .. id .. "::::::::60:::::|h[Item " .. id .. "]|h|r" end

describe("WoW adapters", function()
  local ns
  after_each(function() wow.uninstall() end)

  describe("Api", function()
    before_each(function() wow.install(); ns = addon.loadWith(ADAPTERS) end)

    it("parses item ids from links", function()
      assert.equal(4306, ns.Api.itemIDFromLink(link(4306)))
      assert.is_nil(ns.Api.itemIDFromLink(nil))
    end)

    it("detects whether a nested API exists", function()
      _G.C_Foo = { Bar = function() end }
      assert.is_true(ns.Api.has("C_Foo.Bar"))
      assert.is_false(ns.Api.has("C_Foo.Missing"))
      assert.is_false(ns.Api.has("C_Nope.Bar"))
      _G.C_Foo = nil
    end)
  end)

  describe("ItemInfo", function()
    it("returns item details and caches complete results", function()
      local calls = 0
      wow.install({
        GetItemInfo = function(id)
          calls = calls + 1
          return "Thing", link(id), 2, 38, 30, "Armor", "Cloth", 1, "INVTYPE_CHEST", 123, 450, 4, 1
        end,
      })
      ns = addon.loadWith(ADAPTERS)
      local info = ns.ItemInfo.get(5)
      assert.same({ name = "Thing", link = link(5), quality = 2, itemLevel = 38, classID = 4,
        sellPrice = 450, texture = 123 }, info)
      ns.ItemInfo.get(5)
      assert.equal(1, calls)
    end)

    it("returns nil while the item is not cached by the client", function()
      wow.install()
      ns = addon.loadWith(ADAPTERS)
      assert.is_nil(ns.ItemInfo.get(5))
    end)
  end)

  describe("Market", function()
    before_each(function() wow.install(); ns = addon.loadWith(ADAPTERS) end)

    it("keys markets by realm and faction, or Neutral at goblin towns", function()
      assert.equal("Forever|Horde", ns.Market.key("Forever", "Horde", "Orgrimmar"))
      assert.equal("Forever|Neutral", ns.Market.key("Forever", "Alliance", "Booty Bay"))
      assert.is_true(ns.Market.isNeutralKey("Forever|Neutral"))
      assert.equal("Neutral AH", ns.Market.label("Forever|Neutral"))
      assert.equal("Horde AH", ns.Market.label("Forever|Horde"))
    end)

    it("reads the current market from the game", function()
      _G.GetSubZoneText = function() return "Gadgetzan" end
      local key, neutral = ns.Market.current()
      assert.equal("Forever|Neutral", key)
      assert.is_true(neutral)
    end)
  end)

  describe("Scanner", function()
    local replicate, events, prices, db, now

    before_each(function()
      replicate = {
        -- name, texture, count, quality, usable, level, levelType, minBid, minIncrement,
        -- buyout, bid, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAllInfo
        { "Silk", 1, 20, 1, true, 1, "", 1, 1, 2000, 0, false, nil, "a", "a", 0, 4306, true },
        { "Silk", 1, 10, 1, true, 1, "", 1, 1, 1500, 0, false, nil, "b", "b", 0, 4306, true },
        { "Bid only", 1, 1, 1, true, 1, "", 1, 1, 0, 0, false, nil, "c", "c", 0, 99, true },
      }
      now = 100000
      wow.install({
        C_AuctionHouse = {
          ReplicateItems = function() end,
          GetNumReplicateItems = function() return #replicate end,
          GetReplicateItemInfo = function(i) return unpack(replicate[i + 1]) end,
        },
        time = function() return now end,
      })
      ns = addon.loadWith(ADAPTERS)
      db = {}
      prices = ns.PriceDB.new(db, function() return now end)
      events = ns.Events.new()
    end)

    it("scans, stores unit prices and announces completion", function()
      local scanner = ns.Scanner.new(prices, events, db)
      local result
      events:on("scanComplete", function(r) result = r end)
      assert.is_true(scanner:start("Forever|Horde"))
      scanner:onEvent("REPLICATE_ITEM_LIST_UPDATE")
      assert.equal(1, result.itemCount)
      assert.equal(100, prices:getInfo("Forever|Horde", 4306).low) -- 2000/20
      assert.is_false(scanner.running)
    end)

    it("refuses a second scan inside the 15 minute server limit", function()
      local scanner = ns.Scanner.new(prices, events, db)
      scanner:start("Forever|Horde")
      scanner:onEvent("REPLICATE_ITEM_LIST_UPDATE")
      local ok, wait = scanner:start("Forever|Horde")
      assert.is_false(ok)
      assert.equal(900, wait)
      now = now + 901
      assert.is_true((scanner:start("Forever|Horde")))
    end)

    it("ignores the update event when no scan is running", function()
      local scanner = ns.Scanner.new(prices, events, db)
      scanner:onEvent("REPLICATE_ITEM_LIST_UPDATE")
      assert.same({}, prices:markets())
    end)
  end)

  describe("Professions", function()
    it("reads profession skills from the skill list", function()
      local lines = {
        { "Professions", true }, { "Enchanting", false, false, 150 }, { "Tailoring", false, false, 75 },
        { "Defense", false, false, 300 },
      }
      wow.install({
        GetNumSkillLines = function() return #lines end,
        GetSkillLineInfo = function(i) return unpack(lines[i]) end,
      })
      ns = addon.loadWith(ADAPTERS)
      assert.same({ Enchanting = 150, Tailoring = 75 }, ns.Professions.read())
    end)

    it("falls back to GetProfessions on clients without the skill list", function()
      wow.install({
        GetProfessions = function() return 1, nil end,
        GetProfessionInfo = function() return "Mining", 0, 200 end,
      })
      ns = addon.loadWith(ADAPTERS)
      assert.same({ Mining = 200 }, ns.Professions.read())
    end)
  end)

  describe("TradeSkillRecorder", function()
    it("records recipes from the classic trade skill window", function()
      local skills = {
        { "Cloth", "header" },
        { "Bolt of Silk Cloth", "optimal", out = 4305, made = { 1, 1 }, reagents = { { 4306, 4 } } },
      }
      wow.install({
        GetTradeSkillLine = function() return "Tailoring", 150, 225 end,
        GetNumTradeSkills = function() return #skills end,
        GetTradeSkillInfo = function(i) return skills[i][1], skills[i][2] end,
        GetTradeSkillItemLink = function(i) return skills[i].out and link(skills[i].out) end,
        GetTradeSkillNumMade = function(i) return unpack(skills[i].made) end,
        GetTradeSkillNumReagents = function(i) return #skills[i].reagents end,
        GetTradeSkillReagentInfo = function(i, r) return "Silk", 1, skills[i].reagents[r][2] end,
        GetTradeSkillReagentItemLink = function(i, r) return link(skills[i].reagents[r][1]) end,
      })
      ns = addon.loadWith(ADAPTERS)
      local db = {}
      local count = ns.TradeSkillRecorder.record(db, "Thrall-Forever")
      assert.equal(1, count)
      local list = ns.TradeSkillRecorder.recipesFor(db, "Thrall-Forever")
      assert.equal(1, #list)
      local r = list[1]
      assert.equal("Bolt of Silk Cloth", r.name)
      assert.equal("Tailoring", r.profession)
      assert.equal(4305, r.outputItemID)
      assert.same({ { itemID = 4306, qty = 4 } }, r.reagents)
      assert.is_true(r.knownByPlayer)

      local forAlt = ns.TradeSkillRecorder.recipesFor(db, "Jaina-Forever")[1]
      assert.is_false(forAlt.knownByPlayer)
      assert.same({ "Thrall-Forever" }, forAlt.crafters)
    end)

    it("records recipes from the modern trade skill API", function()
      wow.install({
        C_TradeSkillUI = {
          GetAllRecipeIDs = function() return { 77 } end,
          GetBaseProfessionInfo = function() return { professionName = "Alchemy" } end,
          GetRecipeSchematic = function()
            return { name = "Healing Potion", outputItemID = 929, quantityMin = 1, quantityMax = 3,
              reagentSlotSchematics = { { quantityRequired = 2, reagents = { { itemID = 2453 } } } } }
          end,
        },
      })
      ns = addon.loadWith(ADAPTERS)
      local db = {}
      assert.equal(1, ns.TradeSkillRecorder.record(db, "Me"))
      local r = ns.TradeSkillRecorder.recipesFor(db, "Me")[1]
      assert.equal(2, r.outputQty)
      assert.equal("Alchemy", r.profession)
    end)

    it("skips recipes whose links are not loaded yet", function()
      wow.install({
        GetTradeSkillLine = function() return "Tailoring", 1, 75 end,
        GetNumTradeSkills = function() return 1 end,
        GetTradeSkillInfo = function() return "X", "easy" end,
        GetTradeSkillItemLink = function() return nil end,
      })
      ns = addon.loadWith(ADAPTERS)
      assert.equal(0, ns.TradeSkillRecorder.record({}, "Me"))
    end)
  end)

  describe("LootRecorder", function()
    local slots
    before_each(function()
      slots = {
        { type = 1, link = link(10), sources = { "Creature-0-1-0-1-500-AAA", 2 } },
        { type = 2, sources = { "Creature-0-1-0-1-500-AAA", 150, "Creature-0-1-0-1-500-BBB", 50 } },
      }
      wow.install({
        GetNumLootItems = function() return #slots end,
        GetLootSlotType = function(s) return slots[s].type end,
        GetLootSlotLink = function(s) return slots[s].link end,
        GetLootSourceInfo = function(s) return unpack(slots[s].sources) end,
      })
      ns = addon.loadWith(ADAPTERS)
    end)

    it("counts kills on open and records only the slots actually looted", function()
      local loot = ns.LootDB.new({})
      local taken = {}
      local rec = ns.LootRecorder.new(loot, function(items) taken[#taken + 1] = items end)
      rec:onEvent("LOOT_OPENED")
      assert.equal(2, loot:get(500).kills)
      rec:onEvent("LOOT_SLOT_CLEARED", 2) -- take the coin only
      rec:onEvent("LOOT_CLOSED")
      local m = loot:get(500)
      assert.equal(200, m.copper)
      assert.is_nil(m.drops[10])
      assert.equal(0, #taken)
    end)

    it("reports looted items for the session tracker", function()
      local loot = ns.LootDB.new({})
      local taken
      local rec = ns.LootRecorder.new(loot, function(items) taken = items end)
      rec:onEvent("LOOT_OPENED")
      rec:onEvent("LOOT_SLOT_CLEARED", 1)
      assert.same({ { itemID = 10, qty = 2 } }, taken)
      assert.equal(2, loot:get(500).drops[10])
    end)
  end)

  describe("Nameplates", function()
    before_each(function() wow.install(); ns = addon.loadWith(ADAPTERS) end)

    it("marks mobs above the value threshold with enough kills", function()
      local s = { mobMinValue = 1000, mobMinKills = 5 }
      assert.is_true(ns.Nameplates.shouldMark(1500, 5, s))
      assert.is_false(ns.Nameplates.shouldMark(1500, 4, s))
      assert.is_false(ns.Nameplates.shouldMark(500, 50, s))
      assert.is_false(ns.Nameplates.shouldMark(nil, nil, s))
    end)

    it("adds and removes a marker on a nameplate", function()
      local plate = require("helpers.wow_mock").frame(nil, "Plate")
      _G.C_NamePlate = { GetNamePlateForUnit = function() return plate end }
      _G.UnitGUID = function() return "Creature-0-1-0-1-500-AAA" end
      local np = ns.Nameplates.new({
        settings = { mobMinValue = 1, mobMinKills = 1, showNameplates = true },
        valueOf = function() return 5000, 3 end,
      })
      np:onEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
      assert.is_true(plate.ForeverGoldMarker.shown)
      np:onEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
      assert.is_false(plate.ForeverGoldMarker.shown)
    end)
  end)

  describe("Merchant", function()
    it("reads merchant items, skipping token-cost items", function()
      local items = {
        { "Thread", 1, 100, 5, -1, true, true, false, id = 2321 },
        { "Token thing", 1, 0, 1, -1, true, true, true, id = 9 },
      }
      wow.install({
        GetMerchantNumItems = function() return #items end,
        GetMerchantItemInfo = function(i) return unpack(items[i]) end,
        GetMerchantItemID = function(i) return items[i].id end,
      })
      ns = addon.loadWith(ADAPTERS)
      local list = ns.Merchant.read()
      assert.same({ { index = 1, itemID = 2321, price = 100, stack = 5, available = -1 } }, list)
      local vendorPrices = {}
      ns.Merchant.recordPrices(list, vendorPrices)
      assert.equal(20, vendorPrices[2321])
    end)
  end)

  describe("Tooltip", function()
    before_each(function() wow.install(); ns = addon.loadWith(ADAPTERS) end)

    it("builds item lines with value, vendor, disenchant and best action", function()
      local lines = ns.Tooltip.itemLines(1, 2, {
        info = function() return { value = 1000, low = 900, days = 3, ageDays = 0 } end,
        options = function() return { auction = 950, vendor = 100 } end,
        best = function() return "auction", 950 end,
      })
      assert.same({ "AH value", "10s  x2 = 20s" }, lines[1])
      assert.same({ "AH lowest", "9s" }, lines[2])
      assert.same({ "Vendor", "1s  x2 = 2s" }, lines[3])
      assert.same({ "Best: Auction", "9s 50c" }, lines[#lines])
    end)

    it("warns when price data is old", function()
      local lines = ns.Tooltip.itemLines(1, 1, {
        info = function() return { value = 1000, low = 900, days = 3, ageDays = 4 } end,
        options = function() return { auction = 950 } end,
        best = function() return "auction", 950 end,
      })
      local found = false
      for _, l in ipairs(lines) do if l[1]:find("4 days old") then found = true end end
      assert.is_true(found)
    end)

    it("shows nothing for items with no data", function()
      local lines = ns.Tooltip.itemLines(1, 1, {
        info = function() return nil end,
        options = function() return {} end,
        best = function() return nil end,
      })
      assert.same({}, lines)
    end)

    it("builds unit lines for learned mobs", function()
      local lines = ns.Tooltip.unitLines(500, {
        expected = function() return 2500, 12 end,
        topDrops = function() return { { itemID = 10, perKill = 0.25, value = 2000 } } end,
        nameOf = function() return "Runecloth" end,
      })
      assert.equal("Loot per kill", lines[1][1])
      assert.matches("25s", lines[1][2])
      assert.matches("12 kills", lines[1][2])
      assert.matches("Runecloth", lines[2][1])
    end)

    it("returns no unit lines for unknown mobs", function()
      assert.same({}, ns.Tooltip.unitLines(1, { expected = function() return nil end }))
    end)
  end)
end)
