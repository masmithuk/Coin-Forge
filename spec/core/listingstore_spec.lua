local addon = require("helpers.addon")

describe("ListingStore", function()
  local LS
  before_each(function() LS = addon.loadCore().ListingStore end)

  it("round-trips listings through the compact saved form", function()
    local listings = { [4306] = { { price = 100, count = 5 }, { price = 120, count = 2 } }, [2589] = {} }
    local saved = LS.save({ listings = listings, itemCount = 2, marketKey = "Forever|Horde" }, 5000)
    assert.is_string(saved.items[4306])
    local result = LS.load(saved)
    assert.equal("Forever|Horde", result.marketKey)
    assert.equal(5000, result.time)
    assert.same({ { price = 100, count = 5 }, { price = 120, count = 2 } }, result.listings[4306])
    assert.is_nil(result.listings[2589])
    assert.equal(1, result.itemCount)
  end)

  it("keeps only the cheapest price levels per item", function()
    local list = {}
    for i = 1, 30 do list[i] = { price = i, count = 1 } end
    local result = LS.load(LS.save({ listings = { [1] = list }, marketKey = "m" }, 1))
    assert.equal(LS.MAX_LEVELS, #result.listings[1])
    assert.equal(LS.MAX_LEVELS, result.listings[1][LS.MAX_LEVELS].price)
  end)

  it("updates one item in the saved form", function()
    local saved = LS.save({ listings = { [1] = { { price = 5, count = 1 } } }, marketKey = "m" }, 1)
    LS.setItem(saved, 1, { { price = 7, count = 3 } })
    LS.setItem(saved, 2, nil)
    assert.same({ { price = 7, count = 3 } }, LS.load(saved).listings[1])
  end)

  it("ignores missing or damaged data", function()
    assert.is_nil(LS.load(nil))
    assert.is_nil(LS.load({ items = {} })) -- no market
    local result = LS.load({ marketKey = "m", time = 1, items = { [1] = "garbage" } })
    assert.is_nil(result.listings[1])
  end)
end)
