local addon = require("helpers.addon")

describe("Disenchant", function()
  local ns, DE, I
  before_each(function()
    ns = addon.loadCore()
    DE = ns.Disenchant
    I = ns.Data.Disenchant.items
  end)

  local ARMOR, WEAPON, CONSUMABLE = 4, 2, 0

  it("only accepts uncommon to epic weapons and armor", function()
    assert.is_true(DE.isDisenchantable({ quality = 2, itemLevel = 20, classID = ARMOR }))
    assert.is_true(DE.isDisenchantable({ quality = 4, itemLevel = 60, classID = WEAPON }))
    assert.is_false(DE.isDisenchantable({ quality = 1, itemLevel = 20, classID = ARMOR }))
    assert.is_false(DE.isDisenchantable({ quality = 5, itemLevel = 60, classID = ARMOR }))
    assert.is_false(DE.isDisenchantable({ quality = 2, itemLevel = 20, classID = CONSUMABLE }))
    assert.is_false(DE.isDisenchantable(nil))
  end)

  it("gives mostly dust for uncommon armor", function()
    local out = DE.outcome({ quality = 2, itemLevel = 18, classID = ARMOR })
    assert.same({ itemID = I.STRANGE_DUST, chance = 0.75, min = 2, max = 3 }, out[1])
    assert.same({ itemID = I.GREATER_MAGIC, chance = 0.20, min = 1, max = 2 }, out[2])
    assert.same({ itemID = I.SMALL_GLIMMERING, chance = 0.05, min = 1, max = 1 }, out[3])
  end)

  it("swaps dust and essence chances for uncommon weapons", function()
    local out = DE.outcome({ quality = 2, itemLevel = 18, classID = WEAPON })
    assert.equal(0.20, out[1].chance) -- dust
    assert.equal(0.75, out[2].chance) -- essence
  end)

  it("omits zero-chance outputs", function()
    local out = DE.outcome({ quality = 2, itemLevel = 10, classID = ARMOR })
    assert.equal(2, #out)
  end)

  it("gives shards for rares and multiple shards for epics", function()
    assert.same({ { itemID = I.LARGE_GLOWING, chance = 1, min = 1, max = 1 } },
      DE.outcome({ quality = 3, itemLevel = 38, classID = ARMOR }))
    assert.same({ { itemID = I.SMALL_RADIANT, chance = 1, min = 2, max = 4 } },
      DE.outcome({ quality = 4, itemLevel = 42, classID = WEAPON }))
  end)

  it("knows the enchanting skill an item needs", function()
    assert.equal(1, DE.requiredSkill({ itemLevel = 15 }))
    assert.equal(100, DE.requiredSkill({ itemLevel = 40 }))
    assert.equal(225, DE.requiredSkill({ itemLevel = 63 }))
  end)

  it("computes expected value from material prices", function()
    local prices = { [I.STRANGE_DUST] = 100, [I.GREATER_MAGIC] = 1000, [I.SMALL_GLIMMERING] = 2000 }
    local ev, complete = DE.expectedValue({ quality = 2, itemLevel = 18, classID = ARMOR },
      function(id) return prices[id] end)
    -- 0.75*2.5*100 + 0.20*1.5*1000 + 0.05*1*2000 = 187.5 + 300 + 100
    assert.equal(587, ev)
    assert.is_true(complete)
  end)

  it("flags expected value as incomplete when a material has no price", function()
    local ev, complete = DE.expectedValue({ quality = 3, itemLevel = 38, classID = ARMOR },
      function() return nil end)
    assert.equal(0, ev)
    assert.is_false(complete)
  end)

  it("returns nil expected value for items that cannot be disenchanted", function()
    assert.is_nil(DE.expectedValue({ quality = 1, itemLevel = 10, classID = ARMOR }, function() return 1 end))
  end)
end)

describe("Conversions", function()
  local ns, Conv
  before_each(function()
    ns = addon.loadCore()
    Conv = ns.Conversions
  end)

  it("defines combine and split for every essence tier", function()
    local all = Conv.all()
    assert.equal(10, #all)
    local c = Conv.byKey("combine:10938")
    assert.same({ { 10938, 3 } }, c.inputs)
    assert.same({ { 10939, 1 } }, c.outputs)
  end)

  it("evaluates cost, revenue and profit", function()
    local c = Conv.byKey("combine:10938")
    local buy = { [10938] = 100 }
    local sell = { [10939] = 500 }
    local r = Conv.evaluate(c, function(id) return buy[id] end, function(id) return sell[id] end)
    assert.same({ cost = 300, revenue = 500, profit = 200 }, r)
  end)

  it("lists every conversion with its current profit or loss, best first", function()
    local buy = { [10938] = 100, [10939] = 500 }
    local sell = { [10938] = 95, [10939] = 475 }
    local rows = Conv.evaluateAll(
      { Conv.byKey("combine:10938"), Conv.byKey("split:10939"), Conv.byKey("combine:10998") },
      function(id) return buy[id] end, function(id) return sell[id] end)
    assert.equal(3, #rows)
    assert.equal("combine:10938", rows[1].conversion.key)
    assert.equal(175, rows[1].profit)  -- 475 - 300
    assert.equal(-215, rows[2].profit) -- 285 - 500
    assert.is_nil(rows[3].profit)      -- astral essences have no prices
  end)

  it("returns nil when a price is missing", function()
    local c = Conv.byKey("split:10939")
    assert.is_nil(Conv.evaluate(c, function() return 1 end, function() return nil end))
  end)
end)
