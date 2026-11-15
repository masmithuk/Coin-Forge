local addon = require("helpers.addon")

describe("Crafting", function()
  local ns, Crafting
  before_each(function()
    ns = addon.loadCore()
    Crafting = ns.Crafting
  end)

  -- Bolt of Silk Cloth: 4 Silk Cloth -> 1 Bolt
  local bolt = {
    key = "Tailoring:3839", name = "Bolt of Silk Cloth", profession = "Tailoring",
    outputItemID = 4305, outputQty = 1, reagents = { { itemID = 4306, qty = 4 } },
  }
  -- Recipe with a vendor reagent (thread)
  local shirt = {
    key = "Tailoring:1", name = "Shirt", profession = "Tailoring",
    outputItemID = 900, outputQty = 1,
    reagents = { { itemID = 4305, qty = 2 }, { itemID = 2321, qty = 1 } },
  }

  local function ctx(buy, vendor, sell)
    return {
      buyPrice = function(id) return buy[id] end,
      vendorBuy = function(id) return vendor[id] end,
      sellValue = function(id) return sell[id] end,
    }
  end

  it("uses the cheaper of AH and vendor for each reagent", function()
    local c = ctx({ [2321] = 500 }, { [2321] = 100 }, {})
    assert.equal(100, Crafting.reagentCost(2321, c))
    c = ctx({ [2321] = 50 }, { [2321] = 100 }, {})
    assert.equal(50, Crafting.reagentCost(2321, c))
    assert.is_nil(Crafting.reagentCost(1, c))
  end)

  it("computes cost, revenue, profit and margin", function()
    local r = Crafting.evaluate(bolt, ctx({ [4306] = 100 }, {}, { [4305] = 600 }))
    assert.equal(400, r.cost)
    assert.equal(600, r.revenue)
    assert.equal(200, r.profit)
    assert.equal(0.5, r.margin)
    assert.same({}, r.missing)
  end)

  it("reports losses as negative profit", function()
    local r = Crafting.evaluate(bolt, ctx({ [4306] = 200 }, {}, { [4305] = 600 }))
    assert.equal(-200, r.profit)
  end)

  it("lists reagents with no price and leaves profit unknown", function()
    local r = Crafting.evaluate(shirt, ctx({ [4305] = 10 }, {}, { [900] = 100 }))
    assert.same({ 2321 }, r.missing)
    assert.is_nil(r.cost)
    assert.is_nil(r.profit)
  end)

  it("multiplies revenue by average output quantity", function()
    local multi = { outputItemID = 5, outputQty = 2.5, reagents = { { itemID = 6, qty = 1 } } }
    local r = Crafting.evaluate(multi, ctx({ [6] = 10 }, {}, { [5] = 100 }))
    assert.equal(250, r.revenue)
  end)

  it("sorts many recipes by profit with unknowns last", function()
    local list = Crafting.evaluateAll({ shirt, bolt }, ctx({ [4306] = 100, [4305] = 10 }, {}, { [4305] = 600 }))
    assert.equal("Bolt of Silk Cloth", list[1].recipe.name)
    assert.is_nil(list[2].profit)
  end)
end)

describe("Appraisal", function()
  local ns, Appraisal
  before_each(function()
    ns = addon.loadCore()
    Appraisal = ns.Appraisal
  end)

  local items = {
    [1] = { quality = 2, itemLevel = 38, classID = 4, sellPrice = 300 },   -- green armor
    [2] = { quality = 0, itemLevel = 10, classID = 15, sellPrice = 50 },   -- grey junk
    [11139] = { quality = 2, itemLevel = 40, classID = 7, sellPrice = 0 }, -- Large Glowing Shard (trade good)
  }

  local function make(values, canDE)
    return Appraisal.new({
      marketValue = function(id) return values[id] end,
      itemInfo = function(id) return items[id] end,
      isNeutral = false,
      canDisenchant = function() return canDE end,
    })
  end

  it("lists auction, vendor and disenchant values", function()
    local a = make({ [1] = 1000, [11137] = 200, [11135] = 300, [11139] = 1000 }, true)
    local o = a:options(1)
    assert.equal(950, o.auction)
    assert.equal(300, o.vendor)
    assert.is_number(o.disenchant)
  end)

  it("picks the best action", function()
    local a = make({ [1] = 100 }, false)
    local action, value = a:best(1)
    assert.equal("vendor", action)
    assert.equal(300, value)

    a = make({ [1] = 100000 }, false)
    action = a:best(1)
    assert.equal("auction", action)
  end)

  it("ignores disenchanting when the player cannot do it", function()
    local a = make({ [11137] = 1e6 }, false)
    assert.is_nil(a:options(1).disenchant)
  end)

  it("values junk at vendor price and unknown items at nothing", function()
    local a = make({}, false)
    assert.equal(50, a:value(2))
    assert.equal(0, a:value(999))
  end)
end)
