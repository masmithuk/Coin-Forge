local addon = require("helpers.addon")

describe("Refining", function()
  local R
  before_each(function() R = addon.loadCore().Refining end)

  local ORE, BAR, CLOTH, BANDAGE = 2771, 3576, 2589, 2581
  local recipes = {
    { name = "Smelt Tin", profession = "Mining", outputItemID = BAR, outputQty = 1,
      reagents = { { itemID = ORE, qty = 1 } }, knownByPlayer = true, crafters = { "Me" } },
    { name = "Heavy Linen Bandage", profession = "First Aid", outputItemID = BANDAGE, outputQty = 1,
      reagents = { { itemID = CLOTH, qty = 2 } }, knownByPlayer = false, crafters = { "Alt" } },
    { name = "Two Reagents", profession = "Mining", outputItemID = 9, outputQty = 1,
      reagents = { { itemID = ORE, qty = 1 }, { itemID = 5, qty = 1 } }, knownByPlayer = true, crafters = { "Me" } },
  }
  local conversions = {
    { key = "combine:10938", name = "Combine Lesser Magic Essence",
      inputs = { { 10938, 3 } }, outputs = { { 10939, 1 } } },
  }

  it("finds single-ingredient recipes and conversions that use an item", function()
    local opts = R.optionsFor(ORE, recipes, conversions)
    assert.equal(1, #opts)
    assert.same({ name = "Smelt Tin", profession = "Mining", outputItemID = BAR, inQty = 1, outQty = 1,
      knownByPlayer = true, crafters = { "Me" } }, opts[1])
    local ess = R.optionsFor(10938, recipes, conversions)[1]
    assert.equal(3, ess.inQty)
    assert.is_true(ess.knownByPlayer) -- anyone can convert essences
  end)

  it("ignores recipes that need more than one ingredient", function()
    assert.equal(1, #R.optionsFor(ORE, recipes, {}))
  end)

  it("values each option per item you start with, after the cut, against selling it as it is", function()
    local prices = { [ORE] = 100, [BAR] = 200, [CLOTH] = 50, [BANDAGE] = 80 }
    local result = R.evaluate(ORE, R.optionsFor(ORE, recipes, conversions), {
      price = function(id) return prices[id] end,
      net = function(gross) return math.floor(gross * 0.95) end,
    })
    assert.equal(95, result.asIs)
    assert.equal(190, result.options[1].valueEach)
    assert.equal(95, result.options[1].gain)
  end)

  it("handles ratios like 2 cloth into 1 bandage", function()
    local prices = { [CLOTH] = 50, [BANDAGE] = 80 }
    local result = R.evaluate(CLOTH, R.optionsFor(CLOTH, recipes, conversions), {
      price = function(id) return prices[id] end,
      net = function(gross) return math.floor(gross * 0.95) end,
    })
    local o = result.options[1]
    assert.equal(38, o.valueEach) -- 76 for the bandage, shared by 2 cloth
    assert.equal(-9, o.gain)      -- worse than selling the cloth (47)
  end)

  it("leaves options without an output price unvalued and sorts the best first", function()
    local opts = {
      { name = "A", outputItemID = 1, inQty = 1, outQty = 1 },
      { name = "B", outputItemID = 2, inQty = 1, outQty = 1 },
      { name = "C", outputItemID = 3, inQty = 1, outQty = 1 },
    }
    local prices = { [1] = 100, [3] = 300, [7] = 10 }
    local result = R.evaluate(7, opts, { price = function(id) return prices[id] end, net = function(g) return g end })
    assert.same({ "C", "A", "B" }, { result.options[1].name, result.options[2].name, result.options[3].name })
    assert.is_nil(result.options[3].valueEach)
  end)

  it("still values options when the item itself has no price", function()
    local result = R.evaluate(ORE, R.optionsFor(ORE, recipes, {}), {
      price = function(id) return id == BAR and 200 or nil end, net = function(g) return g end,
    })
    assert.is_nil(result.asIs)
    assert.equal(200, result.options[1].valueEach)
    assert.is_nil(result.options[1].gain)
  end)
end)
