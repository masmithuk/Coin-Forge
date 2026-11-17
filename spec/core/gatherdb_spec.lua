local addon = require("helpers.addon")

describe("GatherDB", function()
  local ns, gather, db
  before_each(function()
    ns = addon.loadCore()
    db = {}
    gather = ns.GatherDB.new(db)
  end)

  local ORE, STONE = 2770, 2835
  local values = { [ORE] = 10, [STONE] = 2 }
  local function valueOf(id) return values[id] or 0 end

  it("counts each node once, even if its loot window is opened twice", function()
    gather:record("Copper Vein", "Mining", "GameObject-a", { { itemID = ORE, qty = 2 } })
    gather:record("Copper Vein", "Mining", "GameObject-a", { { itemID = STONE, qty = 1 } })
    gather:record("Copper Vein", "Mining", "GameObject-b", { { itemID = ORE, qty = 3 } })
    local n = gather:get("Copper Vein")
    assert.equal(2, n.gathers)
    assert.equal("Mining", n.kind)
    assert.same({ [ORE] = 5, [STONE] = 1 }, n.drops)
    assert.equal(2, db.nodes["Copper Vein"].gathers)
  end)

  it("computes the average value per gather", function()
    gather:record("Copper Vein", "Mining", "a", { { itemID = ORE, qty = 2 } })
    gather:record("Copper Vein", "Mining", "b", { { itemID = ORE, qty = 3 }, { itemID = STONE, qty = 1 } })
    local ev, gathers = gather:expectedValue("Copper Vein", valueOf)
    assert.equal(26, ev) -- (2*10 + 3*10 + 2) / 2
    assert.equal(2, gathers)
    assert.is_nil(gather:expectedValue("Tin Vein", valueOf))
  end)

  it("lists a node's yields with the average amount per gather", function()
    gather:record("Peacebloom", "Herbalism", "a", { { itemID = ORE, qty = 1 } })
    gather:record("Peacebloom", "Herbalism", "b", { { itemID = ORE, qty = 2 }, { itemID = STONE, qty = 1 } })
    local drops = gather:topDrops("Peacebloom", valueOf, 5)
    assert.same({ itemID = ORE, perGather = 1.5, value = 15 }, drops[1])
    assert.same({ itemID = STONE, perGather = 0.5, value = 1 }, drops[2])
  end)

  it("ranks the best nodes to gather, skipping ones gathered too few times", function()
    for i = 1, 3 do gather:record("Tin Vein", "Mining", "t" .. i, { { itemID = ORE, qty = 4 } }) end
    for i = 1, 3 do gather:record("Peacebloom", "Herbalism", "p" .. i, { { itemID = STONE, qty = 1 } }) end
    gather:record("Rare Vein", "Mining", "r", { { itemID = ORE, qty = 99 } })
    local top = gather:topNodes(valueOf, 3, 10)
    assert.equal(2, #top)
    assert.same({ name = "Tin Vein", kind = "Mining", ev = 40, gathers = 3 }, top[1])
  end)
end)
