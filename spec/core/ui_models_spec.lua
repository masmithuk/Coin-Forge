local addon = require("helpers.addon")

describe("Commands", function()
  local Commands
  before_each(function() Commands = addon.loadCore().Commands end)

  it("parses a command and its arguments", function()
    assert.same({ cmd = "config", args = { "minProfit", "1g", "50s" } }, Commands.parse("  CONFIG minProfit 1g 50s "))
    assert.same({ cmd = "", args = {} }, Commands.parse(""))
  end)

  it("dispatches to handlers and falls back to help", function()
    local seen = {}
    local router = Commands.new({
      scan = function(args) seen[#seen + 1] = "scan" .. #args end,
      help = function() seen[#seen + 1] = "help" end,
    })
    router:run("scan now")
    router:run("unknown")
    router:run("")
    assert.same({ "scan1", "help", "help" }, seen)
  end)
end)

describe("PanelModel", function()
  local ns, PM
  before_each(function()
    ns = addon.loadCore()
    PM = ns.PanelModel
  end)

  local opps = {
    { kind = "flip", itemID = 1, profit = 500, canDo = true },
    { kind = "craft", itemID = 2, profit = 400, canDo = false },
    { kind = "disenchant", itemID = 3, profit = 300, canDo = true },
  }

  it("filters by kind and by what the player can do", function()
    assert.equal(3, #PM.filter(opps, { kind = "all" }))
    assert.equal(1, #PM.filter(opps, { kind = "craft" }))
    assert.equal(2, #PM.filter(opps, { kind = "all", onlyCanDo = true }))
  end)

  it("builds display rows", function()
    local row = PM.row({ kind = "flip", itemID = 1, profit = 12345, maxPrice = 501, qty = 3, canDo = true, note = "x" },
      function() return "Silk Cloth" end)
    assert.equal("Silk Cloth", row.name)
    assert.equal("Flip", row.kindLabel)
    assert.equal("1g 23s", row.profit)
    assert.equal("5s 1c", row.price)
    assert.equal("3", row.qty)
  end)

  describe("footer", function()
    local mixed = {
      { kind = "flip", itemID = 1, profit = 500, canDo = true },
      { kind = "craft", itemID = 2, profit = 400, canDo = false },
    }
    local allDoable = { { kind = "flip", itemID = 1, profit = 500, canDo = true } }

    it("says how many deals the toggle is hiding", function()
      local text = PM.footer(mixed, { kind = "all", onlyCanDo = true })
      assert.matches("1 deal", text)
      assert.matches("1 hidden", text)
    end)

    it("says when there is nothing to hide, so the toggle never looks broken", function()
      assert.matches("you can do all of these", PM.footer(allDoable, { kind = "all", onlyCanDo = true }))
      assert.matches("you can do all of these", PM.footer(allDoable, { kind = "all", onlyCanDo = false }))
    end)

    it("counts hidden deals only within the selected tab", function()
      assert.matches("1 hidden", PM.footer(mixed, { kind = "craft", onlyCanDo = true }))
      assert.not_matches("hidden", PM.footer(mixed, { kind = "flip", onlyCanDo = true }))
    end)

    it("is empty when there are no deals at all", function()
      assert.equal("", PM.footer({}, { kind = "all", onlyCanDo = true }))
    end)
  end)

  describe("emptyText", function()
    local base = { running = false, hasResult = false, cooldown = 0, onlyCanDo = false, minHistoryDays = 2 }
    local function with(o)
      local s = {}
      for k, v in pairs(base) do s[k] = v end
      for k, v in pairs(o) do s[k] = v end
      return s
    end

    it("asks you to scan when you can", function()
      assert.matches("Press Scan", PM.emptyText(with({})))
    end)

    it("explains the wait instead of asking you to scan when the cooldown is running", function()
      local text = PM.emptyText(with({ cooldown = 754 }))
      assert.not_matches("Press Scan", text)
      assert.matches("12:34", text)
      assert.matches("15 minutes", text)
    end)

    it("explains an empty scan and the can-do filter", function()
      assert.matches("history", PM.emptyText(with({ hasResult = true })))
      assert.matches("Only what I can do", PM.emptyText(with({ hasResult = true, onlyCanDo = true })))
      assert.matches("Scanning", PM.emptyText(with({ running = true })))
    end)
  end)

  it("summarises counts per kind and total profit", function()
    local s = PM.summary(opps)
    assert.equal(3, s.count)
    assert.equal(1200, s.profit)
    assert.equal(1, s.byKind.flip)
  end)

  it("exposes tabs in display order, only for kinds that have results plus All", function()
    local tabs = PM.tabs(opps)
    assert.equal("all", tabs[1].kind)
    assert.equal(4, #tabs)
    assert.equal("3", tabs[1].count)
  end)
end)

describe("Layout", function()
  local Layout
  before_each(function() Layout = addon.loadCore().Layout end)

  local cols = {
    { key = "name", min = 120, weight = 3, priority = 1 },
    { key = "profit", min = 60, weight = 1, priority = 1 },
    { key = "note", min = 100, weight = 2, priority = 3 },
    { key = "qty", min = 30, weight = 0, priority = 2 },
  }

  it("shares spare width by weight when everything fits", function()
    local out = Layout.columns(400, cols)
    assert.equal(4, #out)
    local total = 0
    for _, c in ipairs(out) do total = total + c.width end
    assert.equal(400, total)
    assert.equal("name", out[1].key)
    assert.equal(30, out[4].width) -- weight 0 keeps its min width
  end)

  it("drops the lowest-priority columns first when narrow", function()
    local out = Layout.columns(220, cols)
    local keys = {}
    for _, c in ipairs(out) do keys[#keys + 1] = c.key end
    assert.same({ "name", "profit", "qty" }, keys)
  end)

  it("keeps original column order and offsets", function()
    local out = Layout.columns(400, cols)
    assert.equal(0, out[1].x)
    assert.equal(out[1].width, out[2].x)
  end)

  it("computes how many rows fit", function()
    assert.equal(10, Layout.visibleRows(250, 20, 50))
    assert.equal(1, Layout.visibleRows(10, 20, 50))
  end)
end)

describe("HomeModel", function()
  local ns, Home
  before_each(function()
    ns = addon.loadCore()
    Home = ns.HomeModel
  end)

  it("describes scan freshness", function()
    assert.equal("Never scanned. Open the auction house and press Scan.", Home.scanStatus(nil, 100))
    assert.equal("Last scan 5 min ago", Home.scanStatus(100, 400))
    assert.equal("Last scan 3 h ago", Home.scanStatus(0, 3 * 3600 + 5))
    assert.equal("Last scan 2 days ago", Home.scanStatus(0, 2 * 86400 + 1))
  end)

  it("explains every feature in a short line", function()
    local features = Home.features()
    assert.is_true(#features >= 6)
    for _, f in ipairs(features) do
      assert.is_string(f.title)
      assert.is_string(f.text)
    end
  end)

  it("builds a getting-started checklist that ticks itself off", function()
    local steps = Home.checklist({ scanned = true, mobsLearned = 0, recipesKnown = 3 })
    assert.is_true(steps[1].done)
    assert.is_false(steps[2].done)
    assert.is_true(steps[3].done)
  end)
end)
