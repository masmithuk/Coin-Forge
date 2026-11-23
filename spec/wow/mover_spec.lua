local addon = require("helpers.addon")
local wow = require("helpers.wow_mock")

describe("Mover", function()
  local ns, ah, panel, store, point

  local function called(frame, name)
    for _, c in ipairs(frame.calls) do if c[1] == name then return c end end
    return nil
  end

  before_each(function()
    wow.install({ InCombatLockdown = function() return false end })
    ns = addon.loadWith({ "src/WoW/Api.lua", "src/UI/Mover.lua" })
    ah = wow.frame(UIParent, "AuctionHouseFrame")
    panel = wow.frame(ah, "CoinForgeAuctionPanel")
    point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 120, 700 }
    ah.GetPoint = function() return unpack(point) end
    store = {}
  end)
  after_each(function() wow.uninstall() end)

  it("drags the auction house by its own window or by the Coin Forge panel", function()
    ns.Mover.attach(ah, store, { panel })
    panel:Fire("OnDragStart")
    assert.truthy(called(ah, "StartMoving"))
    panel:Fire("OnDragStop")
    assert.truthy(called(ah, "StopMovingOrSizing"))
    assert.same({ "TOPLEFT", "BOTTOMLEFT", 120, 700 }, store.point)

    ah.calls = {}
    ah:Fire("OnDragStart")
    assert.truthy(called(ah, "StartMoving"))
  end)

  it("puts the window back where you left it", function()
    store.point = { "TOPLEFT", "BOTTOMLEFT", 50, 600 }
    ns.Mover.apply(ah, store)
    assert.truthy(called(ah, "ClearAllPoints"))
    local set = called(ah, "SetPoint")
    assert.same({ "SetPoint", "TOPLEFT", UIParent, "BOTTOMLEFT", 50, 600 }, set)
  end)

  it("leaves Blizzard's position alone until you move it, or after a reset", function()
    ns.Mover.apply(ah, store)
    assert.is_nil(called(ah, "SetPoint"))
    store.point = { "TOPLEFT", "BOTTOMLEFT", 50, 600 }
    ns.Mover.reset(store)
    ns.Mover.apply(ah, store)
    assert.is_nil(called(ah, "SetPoint"))
  end)

  it("keeps the docked panel on screen too", function()
    panel.width = 440
    ns.Mover.attach(ah, store, { panel })
    ns.Mover.apply(ah, store, panel)
    assert.same({ "SetClampRectInsets", 0, -444, 0, 0 }, called(ah, "SetClampRectInsets"))
  end)

  it("hooks each frame only once, however often the auction house opens", function()
    ns.Mover.attach(ah, store, { panel })
    ns.Mover.attach(ah, store, { panel })
    local starts = 0
    ah.StartMoving = function() starts = starts + 1 end
    panel:Fire("OnDragStart")
    assert.equal(1, starts)
  end)

  it("doesn't move anything in combat", function()
    _G.InCombatLockdown = function() return true end
    ns.Mover.attach(ah, store, { panel })
    panel:Fire("OnDragStart")
    assert.is_nil(called(ah, "StartMoving"))
  end)
end)
