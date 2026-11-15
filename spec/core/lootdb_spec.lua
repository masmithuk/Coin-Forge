local addon = require("helpers.addon")

describe("LootDB", function()
  local ns, loot, db
  before_each(function()
    ns = addon.loadCore()
    db = {}
    loot = ns.LootDB.new(db)
  end)

  local values = { [10] = 1000, [11] = 50 }
  local function valueOf(id) return values[id] or 0 end

  it("counts each GUID as one kill even if looted twice (e.g. skinning)", function()
    loot:record(100, "guid-a", { { itemID = 10, qty = 1 } }, 25)
    loot:record(100, "guid-a", { { itemID = 11, qty = 2 } }, 0)
    loot:record(100, "guid-b", {}, 75)
    local m = loot:get(100)
    assert.equal(2, m.kills)
    assert.equal(100, m.copper)
    assert.same({ [10] = 1, [11] = 2 }, m.drops)
  end)

  it("computes expected value per kill including coin", function()
    loot:record(100, "a", { { itemID = 10, qty = 1 } }, 100)
    loot:record(100, "b", {}, 100)
    local ev, kills = loot:expectedValue(100, valueOf)
    -- (200 coin + 1000 item) / 2 kills
    assert.equal(600, ev)
    assert.equal(2, kills)
  end)

  it("returns nil for unknown mobs", function()
    assert.is_nil(loot:expectedValue(5, valueOf))
  end)

  it("remembers mob names", function()
    loot:setName(100, "Defias Pillager")
    loot:record(100, "a", {}, 1)
    assert.equal("Defias Pillager", loot:get(100).name)
  end)

  it("ranks mobs by value, skipping those under the kill threshold", function()
    loot:record(1, "a", { { itemID = 10, qty = 1 } }, 0) -- only 1 kill
    for i = 1, 3 do loot:record(2, "x" .. i, { { itemID = 11, qty = 1 } }, 0) end
    for i = 1, 3 do loot:record(3, "y" .. i, { { itemID = 10, qty = 1 } }, 0) end
    local top = loot:topMobs(valueOf, 3, 10)
    assert.equal(2, #top)
    assert.equal(3, top[1].npcID)
    assert.equal(1000, top[1].ev)
  end)

  it("lists a mob's most valuable drops with drop rate", function()
    loot:record(1, "a", { { itemID = 10, qty = 1 }, { itemID = 11, qty = 4 } }, 0)
    loot:record(1, "b", {}, 0)
    local drops = loot:topDrops(1, valueOf, 5)
    assert.same({ itemID = 10, perKill = 0.5, value = 500 }, drops[1])
    assert.same({ itemID = 11, perKill = 2, value = 100 }, drops[2])
  end)

  it("persists into the provided table", function()
    loot:record(7, "a", {}, 5)
    assert.equal(1, db.mobs[7].kills)
  end)
end)

describe("Session", function()
  local Session
  before_each(function() Session = addon.loadCore().Session end)

  it("tracks money gained, loot value and gold per hour", function()
    local t = 1000
    local s = Session.new(function() return t end, 50000)
    s:addLoot(20000)
    t = t + 1800 -- half an hour
    local sum = s:summary(60000)
    assert.equal(10000, sum.money)
    assert.equal(20000, sum.loot)
    assert.equal(30000, sum.total)
    assert.equal(60000, sum.perHour)
    assert.equal(1800, sum.elapsed)
  end)

  it("reports zero per hour at the very start", function()
    local s = Session.new(function() return 5 end, 0)
    assert.equal(0, s:summary(0).perHour)
  end)

  it("can be reset", function()
    local t = 0
    local s = Session.new(function() return t end, 0)
    s:addLoot(5)
    t = 10
    s:reset(100)
    assert.equal(0, s:summary(100).total)
  end)
end)
