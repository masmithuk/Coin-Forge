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

    it("reads skills from C_SkillInfo on WoW Forever, expanding collapsed headers first", function()
      local lines = {
        { name = "Secondary Skills", isHeader = true, isCollapsed = false },
        { name = "Cooking", rank = 40 },
        { name = "Professions", isHeader = true, isCollapsed = true },
      }
      local hidden = { { name = "Enchanting", rank = 120 }, { name = "Tailoring", rank = 90 } }
      wow.install({
        C_SkillInfo = {
          GetNumSkillLines = function() return #lines end,
          GetSkillLineInfo = function(i) return lines[i] end,
          ExpandSkillHeader = function(i)
            lines[i].isCollapsed = false
            for n, h in ipairs(hidden) do table.insert(lines, i + n, h) end
          end,
        },
      })
      ns = addon.loadWith(ADAPTERS)
      assert.same({ Cooking = 40, Enchanting = 120, Tailoring = 90 }, ns.Professions.read())
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

    describe("learned recipes (WoW Forever lists unlearned ones too)", function()
      local learned
      before_each(function()
        learned = { [77] = true, [78] = false }
        wow.install({
          C_TradeSkillUI = {
            GetAllRecipeIDs = function() return { 77, 78 } end,
            GetBaseProfessionInfo = function() return { professionName = "First Aid" } end,
            GetRecipeInfo = function(id) return { recipeID = id, learned = learned[id] } end,
            GetRecipeSchematic = function(id)
              return { name = "Recipe " .. id, outputItemID = 1000 + id, quantityMin = 1, quantityMax = 1,
                reagentSlotSchematics = { { quantityRequired = 1, reagents = { { itemID = 2589 } } } } }
            end,
          },
        })
        ns = addon.loadWith(ADAPTERS)
      end)

      it("only marks recipes you've learned as known", function()
        local db = {}
        ns.TradeSkillRecorder.record(db, "Dorf-Shammy")
        local list = ns.TradeSkillRecorder.recipesFor(db, "Dorf-Shammy")
        assert.equal(1, #list)
        assert.equal("Recipe 77", list[1].name)
        assert.is_true(list[1].knownByPlayer)
      end)

      it("can include recipes nobody has learned, marked as such", function()
        local db = {}
        ns.TradeSkillRecorder.record(db, "Dorf-Shammy")
        local list = ns.TradeSkillRecorder.recipesFor(db, "Dorf-Shammy", { includeUnlearned = true })
        assert.equal(2, #list)
        assert.is_false(list[2].knownByPlayer)
        assert.is_false(list[2].learnedBySomeone)
        assert.is_true(list[1].learnedBySomeone)
      end)

      it("corrects recipes that were wrongly recorded as known", function()
        local db = { recipes = { ["First Aid:1078"] = { key = "First Aid:1078", name = "Recipe 78",
          profession = "First Aid", outputItemID = 1078, outputQty = 1, reagents = {},
          crafters = { ["Dorf-Shammy"] = true } } } }
        ns.TradeSkillRecorder.record(db, "Dorf-Shammy")
        assert.is_nil(db.recipes["First Aid:1078"].crafters["Dorf-Shammy"])
        assert.equal(1, #ns.TradeSkillRecorder.recipesFor(db, "Dorf-Shammy"))
      end)

      it("diagnoses which recipe API is used and what it reports", function()
        local d = ns.TradeSkillRecorder.diagnose()
        assert.equal("modern", d.path)
        assert.equal("First Aid", d.profession)
        assert.equal(2, d.total)
        assert.equal(1, d.learned)
        assert.equal(1, d.unlearned)
        assert.is_true(d.hasLearnedFlag)
      end)

      it("keeps other characters who did learn it", function()
        local db = { recipes = { ["First Aid:1078"] = { key = "First Aid:1078", name = "Recipe 78",
          profession = "First Aid", outputItemID = 1078, outputQty = 1, reagents = {},
          crafters = { ["Alt-Shammy"] = true } } } }
        ns.TradeSkillRecorder.record(db, "Dorf-Shammy")
        local r = ns.TradeSkillRecorder.recipesFor(db, "Dorf-Shammy")
        assert.equal(2, #r)
        local alt
        for _, x in ipairs(r) do if x.name == "Recipe 78" then alt = x end end
        assert.same({ "Alt-Shammy" }, alt.crafters)
        assert.is_false(alt.knownByPlayer)
      end)
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
      assert.is_true(plate.CoinForgeMarker.shown)
      np:onEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
      assert.is_false(plate.CoinForgeMarker.shown)
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

    describe("turn into", function()
      local names = { [3576] = "Tin Bar", [2581] = "Heavy Linen Bandage" }
      local function lines(result)
        local out = {}
        ns.Tooltip.refineLines(out, result, function(id) return names[id] end)
        return out
      end

      it("lists what the item can become, per item, with the gain over selling it", function()
        local out = lines({ asIs = 95, options = {
          { name = "Smelt Tin", outputItemID = 3576, inQty = 1, outQty = 1, valueEach = 190, gain = 95,
            knownByPlayer = true },
          { name = "Heavy Linen Bandage", outputItemID = 2581, inQty = 2, outQty = 1, valueEach = 38, gain = -57,
            knownByPlayer = false, crafters = { "Alt-Shammy" } },
        } })
        assert.same({ "Turn into", "" }, { out[1][1], out[1][2] })
        assert.equal("  Tin Bar", out[2][1])
        assert.equal("1s 90c each (+95c)", out[2][2])
        assert.same({ 0.35, 0.9, 0.4 }, out[2][3]) -- better: green
        assert.equal("  Heavy Linen Bandage (2 to 1, Alt-Shammy)", out[3][1])
        assert.equal("38c each (-57c)", out[3][2])
        assert.same({ 0.95, 0.35, 0.35 }, out[3][3]) -- worse: red
      end)

      it("says when the result has no price yet", function()
        local out = lines({ options = { { name = "Smelt Tin", outputItemID = 3576, inQty = 1, outQty = 1,
          knownByPlayer = true } } })
        assert.equal("no price yet", out[2][2])
      end)

      it("shows at most three options and nothing when there are none", function()
        local many = {}
        for i = 1, 5 do many[i] = { name = "R" .. i, outputItemID = i, inQty = 1, outQty = 1, valueEach = 10 } end
        assert.equal(4, #lines({ options = many })) -- heading + 3
        assert.same({}, lines({ options = {} }))
        assert.same({}, lines(nil))
      end)
    end)

    describe("disenchant estimate", function()
      local function lines(estimate)
        return ns.Tooltip.itemLines(1, 1, {
          info = function() return nil end,
          options = function() return {} end,
          best = function() return nil end,
          disenchant = function() return estimate end,
          nameOf = function(id) return ({ [11137] = "Vision Dust", [11135] = "Greater Mystic Essence" })[id] end,
        })
      end

      it("shows the estimate and the likely materials", function()
        local out = lines({ value = 12000, canDo = true, complete = true, outcome = {
          { itemID = 11137, chance = 0.75, min = 1, max = 2, price = 5000 },
          { itemID = 11135, chance = 0.20, min = 1, max = 2, price = 20000 },
        } })
        assert.same({ "Disenchant (estimate)", "1g 20s" }, out[1])
        assert.same({ "  1-2 Vision Dust (75%)", "50s each" }, out[2])
        assert.same({ "  1-2 Greater Mystic Essence (20%)", "2g each" }, out[3])
      end)

      it("says when your Enchanting skill is too low", function()
        local out = lines({ value = 12000, canDo = false, skillNeeded = 150, complete = true, outcome = {} })
        assert.same({ "Disenchant (needs Enchanting 150)", "1g 20s" }, out[1])
      end)

      it("says when material prices are missing", function()
        local out = lines({ value = 0, canDo = true, complete = false, outcome = {
          { itemID = 11137, chance = 1, min = 1, max = 1 },
        } })
        assert.same({ "Disenchant (estimate)", "no material prices yet" }, out[1])
        assert.same({ "  1 Vision Dust (100%)", "?" }, out[2])
      end)
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
