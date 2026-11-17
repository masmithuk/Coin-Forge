-- HomeModel: the words on the home screen and minimap tooltip.
local _, ns = ...

local HomeModel = {}
ns.HomeModel = HomeModel

HomeModel.TAGLINE = "Finds gold in the auction house, at vendors and out in the world."

function HomeModel.scanStatus(lastScan, now)
  if not lastScan then return "Never scanned. Open the auction house and press Scan." end
  local ago = now - lastScan
  if ago < 60 then return "Last scan just now" end
  if ago < 3600 then return ("Last scan %d min ago"):format(math.floor(ago / 60)) end
  if ago < 86400 then return ("Last scan %d h ago"):format(math.floor(ago / 3600)) end
  local days = math.floor(ago / 86400)
  return ("Last scan %d day%s ago"):format(days, days == 1 and "" or "s")
end

function HomeModel.features()
  return {
    { title = "Scan the auction house",
      text = "Press Scan on the Coin Forge tab. Prices build up over days, so scan whenever you visit." },
    { title = "Deals at the auctioneer",
      text = "Flips, vendor snipes, disenchanting, essence conversions, crafts and other-AH arbitrage, best first." },
    { title = "Sell in a click",
      text = "The Sell tab prices everything in your bags, skipping bait and price wars. Check it and press Post." },
    { title = "No-profession money",
      text = "The Conversions tab shows essence combine/split profit. Vendor and From vendor deals need no skills." },
    { title = "Profitable mobs",
      text = "A coin marks mobs worth farming. Values are learned from what you loot, across all your characters." },
    { title = "Gathering",
      text = "Veins and herbs show what they yield per gather. Skinning is shown per corpse, "
        .. "and only counts towards a mob's value if you can skin." },
    { title = "Vendor flips",
      text = "Items a vendor sells for less than the AH pays glow green in the merchant window." },
    { title = "Crafting profit",
      text = "Open a profession window once to record its recipes. "
        .. "Then see profit or loss and \"make it yourself\" tips." },
    { title = "Smarter tooltips",
      text = "Item tooltips show AH value, vendor price, disenchant value and the best thing to do with it." },
    { title = "Session tracker",
      text = "Gold per hour from coin and loot since you logged in. Type /cforge reset to start over." },
  }
end

--- @param state { scanned = bool, mobsLearned = n, recipesKnown = n }
function HomeModel.checklist(state)
  return {
    { text = "Scan the auction house", done = state.scanned == true },
    { text = "Kill and loot a few mobs", done = (state.mobsLearned or 0) > 0 },
    { text = "Open each profession window once", done = (state.recipesKnown or 0) > 0 },
  }
end
