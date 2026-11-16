# ForeverGold — Design

> Renamed to **Coin Forge** (folder `CoinForge`, slash command `/cforge`) in 0.4.0, because other addons
> named ForeverGold already exist on CurseForge. This document is kept as written at the time.

Date: 2026-11-15 · Target: World of Warcraft: Forever (interface 16001, client 1.60.1)

## Intent

A gold-making companion for WoW Forever. It builds its own price history from
manual auction-house scans (the way Auctionator does) and turns that data into
concrete money-making prompts wherever the player is: out in the world, at a
vendor, and at the auctioneer.

## Goals

1. **Manual AH scan** — one button, full-AH replicate scan (the server allows one
   every 15 minutes), stored as daily price snapshots per market.
2. **Profitable mobs** — highlight nearby mobs (nameplates + unit tooltip) whose
   expected loot value per kill is above a threshold.
3. **Vendor flips** — at a merchant, highlight items worth more on the AH (after
   the AH cut) than the vendor charges.
4. **Buy page at the auctioneer** listing opportunities, sorted by total profit:
   - *Flips*: listings well under the item's market value.
   - *Vendor snipes*: listings cheaper than the vendor sell price.
   - *Disenchant*: items whose expected disenchant value beats the price.
   - *Conversions*: e.g. 3 lesser essences → 1 greater essence.
   - *Craft*: recipes whose reagents, bought now, cost less than the output sells for.
   - *Arbitrage*: buy here, sell on another AH (faction ⇄ neutral goblin AH).
   - Filter: "only what my characters can do" (professions + skill).
5. **Crafting profit/loss** for every recipe the player's characters know.
6. **Craft-instead suggestions**: items listed on the AH that a known recipe can make
   more cheaply than the listing price.
7. **Extras**: item tooltip pricing with a "best action" (auction / vendor /
   disenchant), a farming session tracker (gold per hour, loot value), slash commands.

## Non-goals

- Automated buying, posting, or anything that bypasses Blizzard's hardware-event
  rules. Clicking a row runs a normal search in the Blizzard Buy tab; the player buys.
- A shipped loot database. Drop rates are learned from the player's own looting.
- Price sharing between players or an external companion app.

## Anti-goals

- Freezing the client during a scan (results are processed in batches across frames).
- Showing confident numbers from thin data: every opportunity requires a minimum
  amount of price history, configurable.
- Untestable logic tangled up with frames and events.

## Constraints

- Lua 5.1 (WoW's dialect); no external libraries required.
- The modern client: `C_AuctionHouse.ReplicateItems`, `TooltipDataProcessor`, nameplates via
  `C_NamePlate`. Every API call is feature-detected so a missing API disables one
  feature, not the addon.
- WoW Forever is realmless: one mega-realm per ruleset. A *market* is
  `realm | faction` or `realm | Neutral` (Booty Bay, Gadgetzan, Everlook).
- AH cut: 5% faction AH, 15% neutral AH. Deposits are refunded on sale and ignored.

## Approaches considered

1. **Pure core + thin adapters (chosen).** All maths (prices, disenchant, crafting,
   opportunity finders, loot EV) lives in `src/Core` as plain functions over plain
   tables, tested with busted outside the game. `src/WoW` adapters translate WoW
   APIs into those tables; `src/UI` only draws. Cost: a little more plumbing.
   Benefit: real TDD, and Forever API surprises are contained in adapters.
2. **Ace3-based addon.** Faster UI and config, but adds a heavy dependency, and
   most logic would still need extracting to be tested.
3. **Extend Auctionator via its API.** Reuses its scanning, but makes this addon
   depend on another addon's release cadence on a brand-new game version.

## Design

```
ForeverGold.toc
src/Core   Namespace, Events, Money, Stats, Settings, Fees, GUID, PriceDB,
           Disenchant, Conversions, Crafting, Appraisal, LootDB, Opportunities,
           VendorAnalysis, Session, Commands, PanelModel, HomeModel, Layout
src/Data   Disenchant tables, conversion definitions (vanilla values, editable)
src/WoW    Api (feature detection), ItemInfo, Market, Scanner, Professions,
           TradeSkillRecorder, LootRecorder, Nameplates, Merchant, Tooltip, App
src/UI     Widgets, AuctionPanel, MerchantOverlay, HomeScreen, MinimapButton
Main.lua   wiring: SavedVariables, events, slash command
```

### UX (added at the user's request during the build)

- Responsive, UX-first windows: resizable, remembered geometry, columns that hide by
  priority when narrow, tab bars that wrap, a helpful empty state everywhere.
- Buttons only where needed: Scan is the only button on the AH panel; views and
  filters are text tabs that appear only when they have results.
- A home screen (status, getting-started checklist, best deals and mobs, session,
  feature guide) and a minimap coin whose tooltip explains the addon.

- **Price model**: each scan stores, per item, the lowest unit buyout, the 20th
  percentile unit price (robust to one troll listing) and the quantity listed.
  One snapshot per item per day. *Market value* = median of the last 14 daily p20s.
- **Loot model**: per NPC id: kills (deduplicated by GUID), coin, item totals.
  Expected value per kill = (coin + Σ qty × best value) / kills. Only shown after a
  minimum number of kills.
- **Opportunity model**: each finder is `function(ctx) -> {opportunity...}`;
  `Opportunities.findAll` merges and sorts. Adding a new idea = adding a finder.

## Decided by the builder (flag for review)

- Addon name **ForeverGold**; slash command `/fg`.
- Default thresholds: min profit 50s, flip discount 30%, mob EV 50s, mob min kills 5,
  min price history 2 days.
- Disenchant and conversion tables use vanilla values; Forever may differ, so they live
  in data files that are easy to edit.
- English profession/zone names for detection (enUS/enGB clients).
