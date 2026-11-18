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
    { title = "Track record",
      text = "Buys from deals and Sell tab posts are followed until they sell or expire, so you can see "
        .. "what each kind of suggestion really made. Type /cforge history." },
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

-- Track record -----------------------------------------------------------------

HomeModel.TRACK_ORDER = { "flip", "vendorFlip", "vendor", "arbitrage", "disenchant", "conversion",
  "craft", "craftInstead", "sell" }

local function signed(copper)
  copper = math.floor(copper or 0)
  return (copper >= 0 and "+" or "") .. ns.Money.short(copper)
end

local function pct(ratio) return math.floor((ratio or 0) * 100 + 0.5) .. "%" end

local function sellLine(s)
  if s.rounds == 0 then return ("Sell tab: %d still listed"):format(s.open) end
  local line = ("Sell tab: %d posts, %s sold"):format(s.rounds, pct(s.sellRate))
  if s.vsSuggested then line = line .. (" at %s of the suggestion"):format(pct(s.vsSuggested)) end
  line = line .. ", made " .. signed(s.actual)
  if s.open > 0 then line = line .. (" (%d still listed)"):format(s.open) end
  return line
end

local function dealLine(label, s)
  if s.rounds > 0 then
    local detail = ("%d sold, %d unsold"):format(s.sold, s.unsold)
    if s.open > 0 then detail = detail .. (", %d waiting"):format(s.open) end
    return ("%s: %d done, predicted %s, actual %s (%s)"):format(label, s.rounds, signed(s.predicted),
      signed(s.actual), detail)
  elseif s.logged > 0 then
    return ("%s: %d bought, predicted %s (not followed through)"):format(label, s.logged, signed(s.predicted))
  end
  return ("%s: %d waiting"):format(label, s.open)
end

--- One line per suggestion kind with any history: predicted vs actual.
--- @param summary History book:summary()
function HomeModel.trackLines(summary)
  local lines = {}
  for _, kind in ipairs(HomeModel.TRACK_ORDER) do
    local s = summary[kind]
    if s and (s.rounds > 0 or s.open > 0 or s.logged > 0) then
      lines[#lines + 1] = kind == "sell" and sellLine(s) or dealLine(ns.PanelModel.LABELS[kind] or kind, s)
    end
  end
  return lines
end

--- Why the player might clear the track record.
function HomeModel.tidyText(advice)
  return ("Your track record has %d entries going back %d days. Clearing old ones keeps logging in"
    .. " and /reload quick; the totals above are kept."):format(advice.entries, advice.oldestDays)
end
