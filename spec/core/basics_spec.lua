local addon = require("helpers.addon")

describe("Money", function()
  local Money
  before_each(function() Money = addon.loadCore().Money end)

  it("formats copper as g/s/c, omitting empty units", function()
    assert.equal("1g 23s 45c", Money.format(12345))
    assert.equal("2g", Money.format(20000))
    assert.equal("5s 1c", Money.format(501))
    assert.equal("0c", Money.format(0))
  end)

  it("formats negative amounts with a minus sign", function()
    assert.equal("-1s 50c", Money.format(-150))
  end)

  it("rounds fractional copper", function()
    assert.equal("3c", Money.format(2.6))
  end)

  it("formats compactly, dropping copper above 1g", function()
    assert.equal("12g 5s", Money.short(120512))
    assert.equal("5s 1c", Money.short(501))
  end)

  it("parses g/s/c strings and plain numbers", function()
    assert.equal(10203, Money.parse("1g 2s 3c"))
    assert.equal(5000, Money.parse("50s"))
    assert.equal(77, Money.parse("77"))
    assert.is_nil(Money.parse("lots"))
  end)
end)

describe("Stats", function()
  local Stats
  before_each(function() Stats = addon.loadCore().Stats end)

  it("computes the median of odd and even lists without mutating input", function()
    local list = { 5, 1, 3 }
    assert.equal(3, Stats.median(list))
    assert.same({ 5, 1, 3 }, list)
    assert.equal(2.5, Stats.median({ 1, 2, 3, 4 }))
    assert.is_nil(Stats.median({}))
  end)

  it("computes a quantity-weighted percentile", function()
    -- 1 unit at 10, 9 units at 100: the 20th percentile unit costs 100
    local entries = { { price = 10, count = 1 }, { price = 100, count = 9 } }
    assert.equal(100, Stats.weightedPercentile(entries, 0.2))
    assert.equal(10, Stats.weightedPercentile(entries, 0.05))
    assert.is_nil(Stats.weightedPercentile({}, 0.5))
  end)

  it("computes the mean", function()
    assert.equal(2, Stats.mean({ 1, 2, 3 }))
    assert.is_nil(Stats.mean({}))
  end)
end)

describe("Settings", function()
  local Settings
  before_each(function() Settings = addon.loadCore().Settings end)

  it("fills missing keys with defaults and keeps user values", function()
    local saved = { minProfit = 123 }
    local s = Settings.apply(saved)
    assert.equal(123, s.minProfit)
    assert.equal(Settings.defaults.flipDiscount, s.flipDiscount)
  end)

  it("sets a known key from a string, converting the type", function()
    local s = Settings.apply({})
    assert.is_true(Settings.set(s, "mobMinKills", "9"))
    assert.equal(9, s.mobMinKills)
    assert.is_true(Settings.set(s, "minProfit", "1g"))
    assert.equal(10000, s.minProfit)
    assert.is_true(Settings.set(s, "showNameplates", "off"))
    assert.is_false(s.showNameplates)
  end)

  it("rejects unknown keys and bad values", function()
    local s = Settings.apply({})
    local ok, err = Settings.set(s, "nope", "1")
    assert.is_false(ok)
    assert.matches("unknown", err)
    ok = Settings.set(s, "mobMinKills", "abc")
    assert.is_false(ok)
  end)
end)

describe("Fees", function()
  local Fees
  before_each(function() Fees = addon.loadCore().Fees end)

  it("uses a 5% cut on faction AHs and 15% on the neutral AH", function()
    assert.equal(0.05, Fees.cutRate(false))
    assert.equal(0.15, Fees.cutRate(true))
  end)

  it("computes net proceeds after the cut", function()
    assert.equal(9500, Fees.net(10000, false))
    assert.equal(8500, Fees.net(10000, true))
  end)
end)

describe("GUID", function()
  local GUID
  before_each(function() GUID = addon.loadCore().GUID end)

  it("extracts the npc id from creature GUIDs", function()
    assert.equal(1234, GUID.npcID("Creature-0-4372-0-1-1234-0000ABCDEF"))
    assert.equal(99, GUID.npcID("Vehicle-0-1-0-1-99-000"))
  end)

  it("recognises world objects such as veins and herbs", function()
    assert.is_true(GUID.isObject("GameObject-0-1-0-1-1731-000ABC"))
    assert.is_false(GUID.isObject("Creature-0-1-0-1-500-AAA"))
    assert.is_false(GUID.isObject(nil))
  end)

  it("returns nil for players, objects and garbage", function()
    assert.is_nil(GUID.npcID("Player-1234-0ABCDEF0"))
    assert.is_nil(GUID.npcID("GameObject-0-1-0-1-500-000"))
    assert.is_nil(GUID.npcID(nil))
  end)
end)

describe("Events", function()
  local Events
  before_each(function() Events = addon.loadCore().Events end)

  it("delivers payloads to every subscriber and supports unsubscribe", function()
    local bus = Events.new()
    local got = {}
    local off = bus:on("scan", function(n) got[#got + 1] = "a" .. n end)
    bus:on("scan", function(n) got[#got + 1] = "b" .. n end)
    bus:emit("scan", 1)
    off()
    bus:emit("scan", 2)
    assert.same({ "a1", "b1", "b2" }, got)
  end)
end)
