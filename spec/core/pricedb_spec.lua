local addon = require("helpers.addon")

describe("PriceDB", function()
  local PriceDB, now, db, prices
  local DAY = 86400
  local M = "Forever|Horde"

  before_each(function()
    PriceDB = addon.loadCore().PriceDB
    now = 10 * DAY
    db = {}
    prices = PriceDB.new(db, function() return now end)
  end)

  local function scan(market, listings)
    local s = prices:beginScan(market)
    for _, l in ipairs(listings) do s:add(l[1], l[2], l[3]) end
    return s:commit()
  end

  it("records lowest unit price, robust price and quantity per item", function()
    scan(M, { { 100, 50, 1 }, { 100, 200, 4 }, { 100, 300, 5 } })
    local info = prices:getInfo(M, 100)
    assert.equal(50, info.low)
    assert.equal(10, info.qty)
    assert.equal(200, info.value) -- 20th percentile unit of 10 units is a 200c unit
    assert.equal(1, info.days)
    assert.equal(0, info.ageDays)
  end)

  it("returns current listings sorted cheapest first from commit", function()
    local result = scan(M, { { 7, 300, 1 }, { 7, 100, 2 } })
    assert.same({ { price = 100, count = 2 }, { price = 300, count = 1 } }, result.listings[7])
    assert.equal(1, result.itemCount)
  end)

  it("ignores listings without a buyout or with zero count", function()
    scan(M, { { 1, 0, 1 }, { 1, 100, 0 } })
    assert.is_nil(prices:getInfo(M, 1))
  end)

  it("keeps one snapshot per day and replaces same-day scans", function()
    scan(M, { { 1, 100, 1 } })
    scan(M, { { 1, 120, 1 } })
    assert.equal(1, prices:getInfo(M, 1).days)
    assert.equal(120, prices:getInfo(M, 1).value)
  end)

  it("uses the median of recent daily values as market value", function()
    for i, p in ipairs({ 100, 1000, 120, 110 }) do
      now = (10 + i) * DAY
      scan(M, { { 1, p, 1 } })
    end
    assert.equal(115, prices:getValue(M, 1))
    assert.equal(4, prices:getInfo(M, 1).days)
  end)

  it("ages data and reports days since last seen", function()
    scan(M, { { 1, 100, 1 } })
    now = now + 3 * DAY
    assert.equal(3, prices:getInfo(M, 1).ageDays)
  end)

  it("keeps markets separate", function()
    scan(M, { { 1, 100, 1 } })
    assert.is_nil(prices:getValue("Forever|Neutral", 1))
    assert.same({ M }, prices:markets())
  end)

  it("prunes snapshots older than the history window", function()
    scan(M, { { 1, 100, 1 } })
    now = now + 40 * DAY
    scan(M, { { 2, 100, 1 } })
    prices:prune(30)
    assert.is_nil(prices:getInfo(M, 1))
    assert.is_not_nil(prices:getInfo(M, 2))
  end)

  describe("recordItem (live search results for one item)", function()
    it("replaces today's snapshot for that item only", function()
      scan(M, { { 1, 100, 10 }, { 2, 500, 1 } })
      prices:recordItem(M, 1, { { price = 80, count = 3 }, { price = 90, count = 2 } })
      local info = prices:getInfo(M, 1)
      assert.equal(80, info.low)
      assert.equal(5, info.qty)
      assert.equal(1, info.days)
      assert.equal(500, prices:getInfo(M, 2).low)
    end)

    it("adds a new day's snapshot and keeps history", function()
      scan(M, { { 1, 100, 1 } })
      now = now + DAY
      prices:recordItem(M, 1, { { price = 120, count = 1 } })
      assert.equal(2, prices:getInfo(M, 1).days)
      assert.equal(110, prices:getValue(M, 1))
    end)

    it("doesn't count as a full scan", function()
      prices:recordItem(M, 1, { { price = 120, count = 1 } })
      assert.is_nil(prices:lastScan(M))
    end)

    it("ignores an empty result", function()
      prices:recordItem(M, 1, {})
      assert.is_nil(prices:getInfo(M, 1))
    end)
  end)

  it("remembers when each market was last scanned", function()
    assert.is_nil(prices:lastScan(M))
    scan(M, { { 1, 100, 1 } })
    assert.equal(now, prices:lastScan(M))
  end)
end)
