local addon = require("helpers.addon")

describe("SellPricing", function()
  local SP
  before_each(function() SP = addon.loadCore().SellPricing end)

  local settings = { undercut = 1, sellFloor = 0.6, baitShare = 0.2, minHistoryDays = 2 }

  local function suggest(o)
    return SP.suggest({
      listings = o.listings or {},
      value = o.value,
      historyDays = o.historyDays or 5,
      vendorSell = o.vendorSell or 0,
      cutRate = 0.05,
      settings = o.settings or settings,
    })
  end

  local function L(price, count, mine) return { price = price, count = count, mine = mine or false } end

  it("undercuts the cheapest competitor by the undercut amount", function()
    local s = suggest({ value = 1000, listings = { L(950, 5), L(990, 10) } })
    assert.equal("post", s.action)
    assert.equal(949, s.price)
    assert.equal(950, s.competitor)
  end)

  it("matches your own cheapest listing instead of undercutting yourself", function()
    local s = suggest({ value = 1000, listings = { L(950, 5, true), L(990, 10) } })
    assert.equal(950, s.price)
    assert.matches("already the cheapest", s.reason)
  end)

  it("ignores a few bait listings far under the normal price", function()
    -- 2 units at 100c (90% under) against 50 units around 1000c
    local s = suggest({ value = 1000, listings = { L(100, 2), L(980, 20), L(1000, 30) } })
    assert.equal(979, s.price)
    assert.equal(2, s.ignored.qty)
    assert.matches("bait", s.reason)
  end)

  it("refuses to follow a price war down when the history says it's too cheap", function()
    -- a wall of 100 units at 300c (70% under) is most of the supply
    local s = suggest({ value = 1000, listings = { L(300, 100), L(900, 10) } })
    assert.equal(899, s.price)
    assert.equal(100, s.ignored.qty)
    assert.matches("[Pp]rice war", s.reason)
  end)

  it("posts at the floor when everything listed is below it", function()
    local s = suggest({ value = 1000, listings = { L(300, 100) } })
    assert.equal(600, s.price) -- 60% of normal
    assert.matches("[Pp]rice war", s.reason)
  end)

  it("follows the market when there's no trusted history", function()
    local s = suggest({ value = 1000, historyDays = 1, listings = { L(300, 100), L(900, 10) } })
    assert.equal(299, s.price)
  end)

  it("still spots bait without history, using the listings themselves", function()
    local s = suggest({ value = nil, historyDays = 0, listings = { L(10, 1), L(1000, 40), L(1010, 40) } })
    assert.equal(999, s.price)
    assert.equal(1, s.ignored.qty)
  end)

  it("uses market value when nobody else is selling", function()
    local s = suggest({ value = 1234, listings = {} })
    assert.equal(1234, s.price)
    assert.matches("[Nn]o competition", s.reason)
  end)

  it("asks for a manual price when there's no data at all", function()
    local s = suggest({ value = nil, historyDays = 0, listings = {} })
    assert.equal("manual", s.action)
    assert.is_nil(s.price)
  end)

  it("recommends vendoring when the AH pays no more than a vendor", function()
    local s = suggest({ value = 100, listings = { L(100, 5) }, vendorSell = 95 })
    assert.equal("vendor", s.action)
    assert.matches("vendor", s.reason)
  end)

  it("never prices below one copper", function()
    local s = suggest({ value = 1, historyDays = 0, listings = { L(1, 5) } })
    assert.equal(1, s.price)
  end)

  describe("explains every listing so you can check the maths", function()
    it("marks bait, the competitor and the rest", function()
      local s = suggest({ value = 1000, listings = { L(100, 2), L(980, 20), L(1000, 30) } })
      assert.same({ "bait", "undercut", "above" }, { s.listings[1].status, s.listings[2].status,
        s.listings[3].status })
      assert.equal(600, s.floor)
    end)

    it("marks price war listings and your own", function()
      local s = suggest({ value = 1000, listings = { L(300, 100), L(900, 10, true), L(950, 5) } })
      assert.same({ "war", "yours", "above" }, { s.listings[1].status, s.listings[2].status,
        s.listings[3].status })
    end)

    it("does not change the caller's listings", function()
      local input = { L(950, 5) }
      suggest({ value = 1000, listings = input })
      assert.is_nil(input[1].status)
    end)
  end)

  it("reports what you'd receive after the AH cut", function()
    local s = suggest({ value = 1000, listings = { L(1001, 1) } })
    assert.equal(1000, s.price)
    assert.equal(950, s.net)
  end)
end)
