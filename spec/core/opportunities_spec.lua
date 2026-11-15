local addon = require("helpers.addon")

describe("Opportunities", function()
  local ns, Opp
  before_each(function()
    ns = addon.loadCore()
    Opp = ns.Opportunities
  end)

  local GREEN_ARMOR = { quality = 2, itemLevel = 38, classID = 4, sellPrice = 100 }

  -- Builds a context with sensible defaults; override fields per test.
  local function ctx(o)
    local c = {
      listings = o.listings or {},
      value = function(id) return (o.values or {})[id] end,
      history = function(id) return (o.history or {})[id] or 5 end,
      itemInfo = function(id) return (o.items or {})[id] end,
      cutRate = 0.05,
      settings = { minProfit = 100, flipDiscount = 0.3, minHistoryDays = 2 },
      skills = o.skills or {},
      recipes = o.recipes or {},
      conversions = o.conversions or {},
      otherMarkets = o.otherMarkets or {},
      vendorBuy = function(id) return (o.vendorBuy or {})[id] end,
    }
    return c
  end

  describe("flips", function()
    it("finds listings well under market value and totals the profit", function()
      local c = ctx({
        listings = { [1] = { { price = 400, count = 2 }, { price = 750, count = 1 }, { price = 1000, count = 5 } } },
        values = { [1] = 1000 },
      })
      local list = Opp.finders.flip(c)
      assert.equal(1, #list)
      local o = list[1]
      assert.equal("flip", o.kind)
      assert.equal(2, o.qty)          -- 750 isn't 30% under 1000
      assert.equal(800, o.cost)
      assert.equal(1900, o.revenue)   -- 2 * 1000 * 0.95
      assert.equal(1100, o.profit)
      assert.equal(400, o.maxPrice)
      assert.is_true(o.canDo)
    end)

    it("skips items without enough price history", function()
      local c = ctx({
        listings = { [1] = { { price = 1, count = 1 } } },
        values = { [1] = 1000 },
        history = { [1] = 1 },
      })
      assert.same({}, Opp.finders.flip(c))
    end)

    it("skips flips below the minimum profit", function()
      local c = ctx({ listings = { [1] = { { price = 60, count = 1 } } }, values = { [1] = 100 } })
      assert.same({}, Opp.finders.flip(c))
    end)
  end)

  describe("vendor snipes", function()
    it("finds listings below the vendor sell price", function()
      local c = ctx({
        listings = { [2] = { { price = 10, count = 20 }, { price = 200, count = 1 } } },
        items = { [2] = { sellPrice = 50, quality = 1, classID = 7, itemLevel = 1 } },
      })
      local o = Opp.finders.vendor(c)[1]
      assert.equal("vendor", o.kind)
      assert.equal(20, o.qty)
      assert.equal(800, o.profit) -- (50 - 10) * 20
    end)
  end)

  describe("disenchant", function()
    it("finds gear selling for less than its disenchant value", function()
      local I = ns.Data.Disenchant.items
      local c = ctx({
        listings = { [3] = { { price = 500, count = 1 } } },
        items = { [3] = GREEN_ARMOR },
        values = { [I.VISION_DUST] = 1000, [I.GREATER_MYSTIC] = 1000, [I.LARGE_GLOWING] = 1000 },
        skills = { Enchanting = 150 },
      })
      local o = Opp.finders.disenchant(c)[1]
      assert.equal("disenchant", o.kind)
      assert.is_true(o.profit > 0)
      assert.is_true(o.canDo)
    end)

    it("marks it as not doable without enough enchanting skill", function()
      local I = ns.Data.Disenchant.items
      local c = ctx({
        listings = { [3] = { { price = 1, count = 1 } } },
        items = { [3] = GREEN_ARMOR },
        values = { [I.VISION_DUST] = 1000, [I.GREATER_MYSTIC] = 1000, [I.LARGE_GLOWING] = 1000 },
        skills = { Enchanting = 50 },
      })
      local o = Opp.finders.disenchant(c)[1]
      assert.is_false(o.canDo)
      assert.matches("Enchanting 100", o.note)
    end)
  end)

  describe("conversions", function()
    it("buys cheap inputs while each conversion stays profitable", function()
      local conv = { key = "combine:1", name = "Combine", inputs = { { 1, 3 } }, outputs = { { 2, 1 } } }
      local c = ctx({
        conversions = { conv },
        listings = { [1] = { { price = 100, count = 4 }, { price = 200, count = 2 }, { price = 900, count = 10 } } },
        values = { [2] = 1000 },
      })
      local o = Opp.finders.conversion(c)[1]
      -- conversion 1: 3 units @100 = 300 -> 950 (+650)
      -- conversion 2: 1@100 + 2@200 = 500 -> 950 (+450)
      -- conversion 3: 3@900 = 2700 -> loss, stop
      assert.equal("conversion", o.kind)
      assert.equal(6, o.qty)
      assert.equal(800, o.cost)
      assert.equal(1100, o.profit)
    end)
  end)

  describe("crafting", function()
    local recipe = {
      key = "T:1", name = "Bolt", profession = "Tailoring", outputItemID = 20, outputQty = 1,
      reagents = { { itemID = 21, qty = 4 } }, crafters = { "Alt-Forever" }, knownByPlayer = false,
    }

    it("suggests crafts whose reagents bought now cost less than the output sells for", function()
      local c = ctx({
        recipes = { recipe },
        listings = { [21] = { { price = 10, count = 40 } } },
        values = { [20] = 1000 },
      })
      local o = Opp.finders.craft(c)[1]
      assert.equal("craft", o.kind)
      assert.equal(40, o.cost)
      assert.equal(910, o.profit) -- 950 - 40
      assert.is_false(o.canDo)
      assert.matches("Alt%-Forever", o.note)
    end)

    it("suggests crafting instead of buying an over-priced listing", function()
      local c = ctx({
        recipes = { recipe },
        listings = { [20] = { { price = 2000, count = 1 } } },
        values = { [21] = 50 },
      })
      local o = Opp.finders.craftInstead(c)[1]
      assert.equal("craftInstead", o.kind)
      assert.equal(20, o.itemID)
      assert.equal(200, o.cost)       -- 4 * 50
      assert.equal(1800, o.profit)    -- saving vs the cheapest listing
    end)
  end)

  describe("arbitrage", function()
    it("finds items cheaper here than their net value on another AH", function()
      local c = ctx({
        listings = { [5] = { { price = 100, count = 3 } } },
        values = { [5] = 120 },
        otherMarkets = { {
          key = "Forever|Neutral", label = "Neutral AH", cutRate = 0.15,
          value = function() return 1000 end, history = function() return 5 end,
        } },
      })
      local o = Opp.finders.arbitrage(c)[1]
      assert.equal("arbitrage", o.kind)
      assert.equal(3 * (850 - 100), o.profit)
      assert.matches("Neutral AH", o.note)
    end)
  end)

  it("findAll merges every finder and sorts by profit", function()
    local c = ctx({
      listings = {
        [1] = { { price = 100, count = 1 } },
        [2] = { { price = 1, count = 100 } },
      },
      values = { [1] = 10000 },
      items = { [2] = { sellPrice = 20 } },
    })
    local all = Opp.findAll(c)
    assert.equal("flip", all[1].kind)
    assert.equal("vendor", all[2].kind)
  end)

  it("findAll survives a finder that errors", function()
    local c = ctx({})
    local ok = pcall(Opp.findAll, c, { broken = function() error("boom") end })
    assert.is_true(ok)
  end)
end)

describe("VendorAnalysis", function()
  local VA
  before_each(function() VA = addon.loadCore().VendorAnalysis end)

  local function ctx(values)
    return {
      value = function(id) return values[id] end,
      history = function() return 5 end,
      cutRate = 0.05,
      settings = { minProfit = 1000, minHistoryDays = 2 },
    }
  end

  it("flags vendor items worth more on the AH after the cut", function()
    local merchant = {
      { index = 1, itemID = 1, price = 500, stack = 1, available = 2 },
      { index = 2, itemID = 2, price = 500, stack = 5, available = -1 },
      { index = 3, itemID = 3, price = 500, stack = 1, available = -1 },
    }
    local list = VA.evaluate(merchant, ctx({ [1] = 2000, [2] = 120, [3] = 400 }))
    assert.equal(2, #list)
    local first = list[1]
    assert.equal(1, first.index)
    assert.equal(1400, first.profit)      -- 2000*0.95 - 500
    assert.equal(2800, first.totalProfit) -- limited stock of 2
    assert.is_true(first.limited)
    assert.is_true(first.strong)
    assert.equal(2, list[2].index)
    assert.equal(70, list[2].profit)      -- 5*120*0.95 - 500
    assert.is_false(list[2].strong)
  end)
end)
