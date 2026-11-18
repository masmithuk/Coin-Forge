local addon = require("helpers.addon")

describe("History", function()
  local ns, now, h, book
  local DAY = 86400
  local OPTS = { unsoldDays = 14, cut = 0.05 }

  local function byKind(kind) return book:summary(OPTS)[kind] end

  before_each(function()
    ns = addon.loadCore()
    now = 1000 * DAY
    h = ns.History.new({}, function() return now end)
    book = h:market("Forever|Horde")
  end)

  it("a flip bought then sold shows predicted vs actual", function()
    book:buy(4306, 2, 100, { kind = "flip", profit = 150, qty = 2 })
    book:post(4306, 2, 200, 200, 10)
    now = now + DAY
    book:sold(4306, 2, 380)
    local flip = byKind("flip")
    assert.same({ rounds = 1, sold = 1, unsold = 0, open = 0, predicted = 150, actual = 180 },
      { rounds = flip.rounds, sold = flip.sold, unsold = flip.unsold, open = flip.open,
        predicted = flip.predicted, actual = flip.actual }) -- 380 - 200 (deposit refunded on sale)
  end)

  it("counts lost deposits of expired posts against the flip", function()
    book:buy(4306, 1, 100, { kind = "flip", profit = 90, qty = 1 })
    book:post(4306, 1, 200, nil, 10)
    book:expired(4306, 1)
    book:post(4306, 1, 180, nil, 10)
    book:sold(4306, 1, 171)
    assert.equal(171 - 100 - 10, byKind("flip").actual)
  end)

  it("an unsold flip counts as a loss after 14 days, then is corrected if it sells", function()
    book:buy(4306, 2, 100, { kind = "flip", profit = 150, qty = 2 })
    book:post(4306, 2, 200, 200, 0)
    now = now + 3 * DAY
    assert.equal(1, byKind("flip").open)
    assert.equal(0, byKind("flip").rounds)
    now = now + 12 * DAY
    assert.same({ 1, 1, -200 }, { byKind("flip").rounds, byKind("flip").unsold, byKind("flip").actual })
    book:sold(4306, 2, 380)
    assert.same({ 1, 0, 180 }, { byKind("flip").sold, byKind("flip").unsold, byKind("flip").actual })
  end)

  it("matches sales oldest first across partial commodity sales", function()
    book:post(2589, 20, 10, 10, 0)
    book:post(2589, 10, 12, 12, 0)
    book:sold(2589, 5, nil) -- estimated from the post: 5 x 10 less 5%
    local sell = byKind("sell")
    assert.equal(2, sell.open)
    book:sold(2589, 20, nil)
    sell = byKind("sell")
    assert.equal(1, sell.sold) -- the first post, all 20 sold
    assert.equal(1, sell.open) -- 5 of the second still listed
    assert.equal(math.floor(20 * 10 * 0.95), sell.actual)
  end)

  it("sell-tab posts report sell rate and price vs suggestion", function()
    book:post(1, 1, 90, 100, 0)  -- you lowered it to 90%
    book:post(2, 1, 100, 100, 5)
    book:sold(1, 1, nil)
    book:expired(2, 1)
    local sell = byKind("sell")
    assert.same({ 2, 1, 1 }, { sell.rounds, sell.sold, sell.unsold })
    assert.equal(0.5, sell.sellRate)
    assert.near(0.9, sell.vsSuggested, 0.001)
    assert.equal(math.floor(90 * 0.95) - 5, sell.actual)
  end)

  it("pairs vendor snipes with vendor sales", function()
    book:buy(5, 3, 40, { kind = "vendor", profit = 30, qty = 3 })
    book:vendorSale(5, 3, 50)
    assert.same({ 1, 30, 30 }, { byKind("vendor").sold, byKind("vendor").predicted, byKind("vendor").actual })
  end)

  it("logs crafts and conversions without matching an outcome", function()
    book:buy(7, 1, 500, { kind = "craft", profit = 200, qty = 1 })
    local craft = byKind("craft")
    assert.same({ 1, 200 }, { craft.logged, craft.predicted })
    assert.is_nil(craft.actual)
  end)

  it("ignores sales and expiries with no logged post", function()
    book:sold(9, 1, 100)
    book:expired(9, 1)
    book:buy(9, 1, 50, nil) -- an untagged buy
    assert.same({}, book:summary(OPTS))
  end)

  it("scales the prediction to the quantity actually bought", function()
    book:buy(4306, 1, 100, { kind = "flip", profit = 300, qty = 3 })
    assert.equal(100, select(2, next(book:rounds(OPTS))).predicted)
  end)

  it("clear folds closed rounds into weekly totals and keeps young open ones", function()
    book:buy(4306, 2, 100, { kind = "flip", profit = 150, qty = 2 })
    book:post(4306, 2, 200, 200, 0)
    book:sold(4306, 2, 380)
    book:post(1, 1, 100, 100, 0)
    book:expired(1, 1)
    now = now + 40 * DAY
    book:post(2, 1, 50, 50, 0) -- recent and still listed
    local before = book:summary(OPTS)
    local removed = book:clear(30, OPTS)
    assert.equal(5, removed)
    assert.equal(1, #book.data.entries)
    assert.same(before, book:summary(OPTS))
  end)

  it("clearing everything keeps the totals", function()
    book:post(1, 1, 100, 100, 0)
    book:sold(1, 1, 95)
    local before = book:summary(OPTS)
    book:clear(nil, OPTS)
    assert.equal(0, #book.data.entries)
    assert.same(before, book:summary(OPTS))
  end)

  it("keeps entries a remaining round still needs", function()
    book:post(1, 2, 100, 100, 0)
    book:sold(1, 1, 95)
    now = now + 5 * DAY
    book:clear(nil, OPTS) -- the post is still open and young
    assert.equal(2, #book.data.entries)
  end)

  it("suggests tidying at the entry or age limit", function()
    local limits = { entries = 3, days = 60 }
    book:post(1, 1, 100, 100, 0)
    assert.is_nil(book:tidyAdvice(limits))
    now = now + 61 * DAY
    assert.same({ entries = 1, oldestDays = 61 }, book:tidyAdvice(limits))
    book:clear(nil, OPTS)
    book:post(1, 1, 1, 1, 0); book:post(1, 1, 1, 1, 0); book:post(1, 1, 1, 1, 0)
    assert.equal(3, book:tidyAdvice(limits).entries)
  end)

  it("keeps each market separate", function()
    book:post(1, 1, 100, 100, 0)
    assert.same({}, h:market("Forever|Neutral"):summary(OPTS))
  end)
end)
