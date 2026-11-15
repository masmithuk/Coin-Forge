local addon = require("helpers.addon")
local wow = require("helpers.wow_mock")

local function link(id) return "|cffffffff|Hitem:" .. id .. "::::::::60:::::|h[Item " .. id .. "]|h|r" end

-- A fake bag: bags[bag][slot] = { itemID, stackCount, commodity, bound }
local function installBags(bags, extra)
  local posted = {}
  local env = {
    C_Container = {
      GetContainerNumSlots = function(bag) return bags[bag] and 4 or 0 end,
      GetContainerItemInfo = function(bag, slot)
        local i = bags[bag] and bags[bag][slot]
        if not i then return nil end
        return { itemID = i[1], stackCount = i[2], hyperlink = link(i[1]), isBound = i[4] }
      end,
    },
    ItemLocation = {
      CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
    },
    C_Item = { DoesItemExist = function(loc) return bags[loc.bag] and bags[loc.bag][loc.slot] ~= nil end },
    Enum = { ItemCommodityStatus = { Item = 1, Commodity = 2 },
      AuctionHouseSortOrder = { Price = 0 }, TooltipDataType = { Item = 0, Unit = 2 } },
    C_AuctionHouse = {
      IsSellItemValid = function(loc) return not bags[loc.bag][loc.slot][4] end,
      GetItemCommodityStatus = function(loc) return bags[loc.bag][loc.slot][3] and 2 or 1 end,
      GetAvailablePostCount = function(loc) return bags[loc.bag][loc.slot][2] * 2 end, -- all stacks
      MakeItemKey = function(id) return { itemID = id } end,
      GetItemKeyFromItem = function(loc) return { itemID = bags[loc.bag][loc.slot][1], itemLevel = 5 } end,
      PostCommodity = function(...) posted[#posted + 1] = { "commodity", ... } return true end,
      PostItem = function(...) posted[#posted + 1] = { "item", ... } return true end,
      CalculateCommodityDeposit = function(_, duration, qty) return 10 * duration * qty end,
      CalculateItemDeposit = function(_, duration, qty) return 7 * duration * qty end,
      IsThrottledMessageSystemReady = function() return true end,
    },
  }
  for k, v in pairs(extra or {}) do env[k] = v end
  wow.install(env)
  return posted
end

local FILES = { "src/WoW/Api.lua", "src/WoW/ItemInfo.lua", "src/WoW/Bags.lua", "src/WoW/SellSearch.lua",
  "src/WoW/Poster.lua" }

describe("Selling adapters", function()
  local ns
  after_each(function() wow.uninstall() end)

  describe("Bags", function()
    it("groups sellable commodities by item and gear by link, skipping bound items", function()
      installBags({
        [0] = { [1] = { 4306, 20, true }, [2] = { 4306, 5, true }, [3] = { 900, 1, false } },
        [1] = { [1] = { 901, 1, false, true } },
      })
      ns = addon.loadWith(FILES)
      local items = ns.Bags.sellable()
      assert.equal(2, #items)
      local silk
      for _, i in ipairs(items) do if i.itemID == 4306 then silk = i end end
      assert.equal(25, silk.count)
      assert.is_true(silk.isCommodity)
      assert.equal(40, silk.postable) -- the server's count across stacks
      assert.same({ bag = 0, slot = 1 }, { bag = silk.bag, slot = silk.slot })
    end)
  end)

  describe("SellSearch", function()
    it("reads live commodity results, marking your own listings", function()
      local searched
      installBags({ [0] = { [1] = { 4306, 20, true } } })
      _G.C_AuctionHouse.SendSearchQuery = function(key) searched = key end
      _G.C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
      _G.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i)
        return ({ { unitPrice = 90, quantity = 5, containsOwnerItem = true },
                  { unitPrice = 100, quantity = 50, containsOwnerItem = false } })[i]
      end
      ns = addon.loadWith(FILES)
      local got
      local search = ns.SellSearch.new(function(item, listings) got = { item = item, listings = listings } end)
      local item = ns.Bags.sellable()[1]
      search:request(item)
      assert.equal(4306, searched.itemID)
      search:onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 9999) -- someone else's search
      assert.is_nil(got)
      search:onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 4306)
      assert.same({ { price = 90, count = 5, mine = true }, { price = 100, count = 50, mine = false } }, got.listings)
    end)

    it("reads live item results, skipping bid-only auctions", function()
      installBags({ [0] = { [1] = { 900, 1, false } } })
      _G.C_AuctionHouse.SendSellSearchQuery = function() end
      _G.C_AuctionHouse.GetNumItemSearchResults = function() return 2 end
      _G.C_AuctionHouse.GetItemSearchResultInfo = function(_, i)
        return ({ { buyoutAmount = nil, quantity = 1 }, { buyoutAmount = 5000, quantity = 1 } })[i]
      end
      ns = addon.loadWith(FILES)
      local got
      local search = ns.SellSearch.new(function(_, listings) got = listings end)
      search:request(ns.Bags.sellable()[1])
      search:onEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 900 })
      assert.same({ { price = 5000, count = 1, mine = false } }, got)
    end)
  end)

  describe("SellView.postState", function()
    before_each(function()
      wow.install()
      ns = addon.loadWith({ "src/UI/Widgets.lua", "src/WoW/Api.lua", "src/WoW/ItemInfo.lua", "src/WoW/Bags.lua",
        "src/WoW/Poster.lua", "src/UI/SellView.lua" })
    end)

    it("is never off without saying why", function()
      local cases = {
        { nil, 5, 10, true, "type a price" },
        { 100, 0, 10, true, "quantity must be between 1 and 10" },
        { 100, 11, 10, true, "quantity must be between 1 and 10" },
        { 100, 5, 10, false, "busy" },
      }
      for _, c in ipairs(cases) do
        local enabled, message = ns.SellView.postState(c[1], c[2], c[3], c[4])
        assert.is_false(enabled)
        assert.matches(c[5], message, 1, true)
      end
      assert.is_true(ns.SellView.postState(100, 5, 10, true))
    end)
  end)

  describe("Poster", function()
    it("posts commodities by unit price and gear as buyout-only", function()
      local posted = installBags({ [0] = { [1] = { 4306, 20, true }, [2] = { 900, 1, false } } })
      ns = addon.loadWith(FILES)
      local items = ns.Bags.sellable()
      local silk, sword = items[1], items[2]
      if silk.itemID ~= 4306 then silk, sword = sword, silk end
      assert.is_true(ns.Poster.post(silk, 123, 20, 2))
      assert.is_true(ns.Poster.post(sword, 5000, 1, 3))
      assert.same({ "commodity", { bag = 0, slot = 1 }, 2, 20, 123 }, posted[1])
      -- no starting bid: nobody can win it for a low bid
      assert.same({ "item", { bag = 0, slot = 2 }, 3, 1, nil, 5000 }, { posted[2][1], posted[2][2], posted[2][3],
        posted[2][4], posted[2][5], posted[2][6] })
    end)

    it("refuses to post an item that has moved or gone", function()
      installBags({ [0] = { [1] = { 4306, 20, true } } })
      ns = addon.loadWith(FILES)
      local silk = ns.Bags.sellable()[1]
      silk.slot = 3
      local ok, reason = ns.Poster.post(silk, 1, 1, 1)
      assert.is_false(ok)
      assert.matches("moved", reason)
    end)

    it("calculates the deposit", function()
      installBags({ [0] = { [1] = { 4306, 20, true } } })
      ns = addon.loadWith(FILES)
      assert.equal(10 * 2 * 5, ns.Poster.deposit(ns.Bags.sellable()[1], 2, 5))
    end)

    it("knows when the AH is ready for another request", function()
      installBags({ [0] = {} })
      ns = addon.loadWith(FILES)
      assert.is_true(ns.Poster.ready())
      _G.C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
      assert.is_false(ns.Poster.ready())
    end)
  end)
end)
