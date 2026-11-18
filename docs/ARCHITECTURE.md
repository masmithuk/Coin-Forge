# Architecture

Coin Forge is split into three layers so the parts that make decisions can be
tested without the game, and the parts that touch the game stay small.

```
            ┌──────────────────────────────────────────────┐
  game ───▶ │ src/WoW   adapters: turn WoW API calls into   │
  events    │           plain tables (Scanner, LootRecorder,│
            │           TradeSkillRecorder, Merchant, ...)  │
            └───────────────┬──────────────────────────────┘
                            │ plain tables
            ┌───────────────▼──────────────────────────────┐
            │ src/Core  pure Lua: prices, disenchanting,    │
            │           crafting, opportunity finders, loot │
            │           value, view models. No WoW globals. │
            └───────────────┬──────────────────────────────┘
                            │ results
            ┌───────────────▼──────────────────────────────┐
            │ src/UI    frames only: AuctionPanel, HomeScreen│
            │           MerchantOverlay, MinimapButton      │
            └──────────────────────────────────────────────┘
```

`src/WoW/App.lua` creates every service and is the only thing the UI and
`Main.lua` talk to. `Main.lua` registers game events and forwards them.

## Modules

### Core (`src/Core`, pure, tested in `spec/core`)

| Module | Responsibility |
|---|---|
| `Namespace` | Sets up the shared `ns` table (`ns.Data` for static data) |
| `Events` | Tiny pub/sub bus (`scanComplete`, `opportunitiesUpdated`, ...) |
| `Money` | Copper formatting (`1g 23s 45c`) and parsing |
| `Stats` | Median, mean, quantity-weighted percentile |
| `Settings` | Defaults, typed setters for `/cforge config` |
| `Fees` | AH cut (5% faction, 15% neutral) |
| `GUID` | NPC id from a creature GUID |
| `ListingStore` | Compact saved copy of the last scan's listings, restored after `/reload` |
| `PriceDB` | Daily price snapshots per market, market value, pruning |
| `Disenchant` | Outcome, expected value and skill needed, from `Data/Disenchant` |
| `Conversions` | Essence combine/split definitions and evaluation |
| `Crafting` | Recipe cost, revenue, profit, margin |
| `Refining` | Single-ingredient recipes and conversions an item can become, valued per input item |
| `Appraisal` | Auction / vendor / disenchant value of an item and the best action |
| `LootDB` | Kills, coin and drops per NPC, plus skinning per corpse; expected value per kill |
| `GatherDB` | Gathers and yields per vein/herb name; value per gather, best nodes |
| `History` | Per-market trade log (buy/post/sold/expired/vendorSale) replayed into rounds (FIFO by item); predicted vs actual summary, weekly totals, clearing that folds into totals, tidy advice |
| `Opportunities` | Deal finders over current listings (see below) |
| `SellPricing` | Suggested posting price: own listings, bait, price wars, undercut, vendor check |
| `VendorAnalysis` | Which merchant items are worth more on the AH |
| `Session` | Gold per hour |
| `Commands` | `/cforge` parsing and routing |
| `PanelModel`, `HomeModel` | Text and filtering for the UI, kept testable |
| `Layout` | Responsive maths: column widths and hiding, rows that fit |

### WoW adapters (`src/WoW`, tested against a fake client in `spec/wow`)

| Module | Reads / hooks |
|---|---|
| `Api` | Feature detection (`Api.has("C_AuctionHouse.ReplicateItems")`), link parsing |
| `ItemInfo` | `GetItemInfo`, cached |
| `Market` | Realm, faction and neutral town → market key such as `"Forever|Horde"` |
| `Scanner` | `C_AuctionHouse.ReplicateItems`, processed in batches across frames; 15-minute cooldown |
| `Professions` | Skill lines → `{ Enchanting = 150, ... }` |
| `TradeSkillRecorder` | Classic trade skill API, falling back to `C_TradeSkillUI` |
| `TradeRecorder` | `hooksecurefunc` on AH buy/post and merchant buy/buyback calls, plus purchase events, sale-mail invoices, the "expired" system message and buyback-list diffs, all written to `History` |
| `LootRecorder` | `LOOT_OPENED` snapshot → `LOOT_SLOT_CLEARED` records only what was taken; a recent Mining/Herb Gathering/Skinning cast (`UNIT_SPELLCAST_SENT`) routes the loot to GatherDB or a mob's skinning |
| `Nameplates` | Coin marker on `C_NamePlate` frames |
| `Merchant` | Merchant stock; remembers vendor prices for crafting costs |
| `Bags` | Sellable bag items (commodities grouped by item, gear by link) |
| `SellSearch` | Live AH search for one item (pages through all results, marks your own listings); records every complete search, including Blizzard's, into `PriceDB` |
| `Poster` | `PostCommodity` / `PostItem` (buyout-only), deposit, throttle check |
| `Tooltip` | `TooltipDataProcessor` post-calls (falls back to `OnTooltipSet*` hooks) |
| `App` | Builds contexts for the finders and exposes one API to the UI |

### UI (`src/UI`, smoke-tested in `spec/wow/ui_smoke_spec.lua`)

| Module | Screen |
|---|---|
| `Widgets` | Window, resize grip, wrapping tab bar, virtual list with responsive columns |
| `AuctionPanel` | Docked beside the AH: Deals and Crafting views |
| `SellView` | Sell tab: bag item list plus editable price, quantity and duration, and the Post button |
| `MerchantOverlay` | Green glow and profit on vendor items, one summary strip |
| `HomeScreen` | Status, checklist, best deals and mobs, session, feature guide |
| `MinimapButton` | Coin on the minimap with an explanatory tooltip; draggable |

## Data flow of a scan

1. The player presses **Scan**. `App:startScan()` → `Scanner:start(marketKey)` calls `ReplicateItems`.
2. `REPLICATE_ITEM_LIST_UPDATE` → `Scanner:process()` reads 1000 auctions per frame into a `PriceDB` scan.
3. `scan:commit()` writes one snapshot per item per day and returns the live listings.
4. `scanComplete` → `App:findOpportunities(result)` builds a context and runs every finder.
5. `opportunitiesUpdated` → `AuctionPanel:Refresh()`. Nameplates also refresh, since item values changed.

Any complete search result for one item (`PriceDB:recordItem`) replaces that item's snapshot for today and
its entry in the current listings, then the finders re-run.

The last scan's listings are also saved in compact form (`ListingStore`: each item's 20 cheapest price
levels) and restored after a `/reload`, so deals don't wait for the next 15-minute scan window.

## Saved data (`CoinForgeDB`, account-wide)

```lua
CoinForgeDB = {
  settings = { minProfit = 5000, ... },
  markets = { ["Forever|Horde"] = { lastScan = t, items = { [itemID] = { snaps = { {day, low, value, qty} } } } } },
  mobs = { [npcID] = { name, kills, copper, drops = { [itemID] = qty } } },
  recipes = { ["Tailoring:4305"] = { name, profession, outputItemID, outputQty, reagents, crafters = { ["Name-Realm"] = true } } },
  vendorPrices = { [itemID] = copperPerUnit },
  lastDeals = { [marketKey] = top 5 deals from that AH's last scan, for the home screen },
  listings = { [marketKey] = { marketKey, time, items = { [itemID] = "price:count,..." } } },
  scanner = { byRealm = { [realm] = last scan start } },  -- 15-minute cooldown per realm
  ui = { home = {geometry}, auctionPanel = {geometry, onlyCanDo}, minimap = { angle }, welcomed = true },
}
```

## Adding a new kind of deal

Opportunities are open for extension. To add one:

1. Write a failing test in `spec/core/opportunities_spec.lua` using the `ctx({...})` helper.
2. Add `function finders.myIdea(ctx) ... end` in `src/Core/Opportunities.lua`. Return a list of
   `{ kind, itemID, qty, maxPrice, cost, revenue, profit, canDo, note }`. The `emit` helper applies
   `minProfit` for you.
3. Add `"myIdea"` to `Opportunities.KINDS`, plus a label and a one-line help text in `PanelModel`.

The panel creates a tab for it automatically, and only when there are results.

## UI principles

- **Content first, few buttons.** The only button is Scan. Views and filters are text tabs that appear only when
  they have results. Rows are clickable, and tooltips explain the rest.
- **Responsive.** Windows resize from the bottom-right grip and remember their size. Lists show as many rows as fit,
  and columns share spare width by weight, hiding the least important first when narrow (`Layout.columns`).
  Tab bars wrap onto new lines.
- **Helpful empty states.** Every empty list says why it's empty and what to do next.
- **Explain in place.** The minimap tooltip, tab tooltips and the home screen guide replace a manual.

## Testing approach

- `spec/helpers/addon.lua` loads files **in `.toc` order** into a fresh namespace, exactly as the client does.
- `spec/helpers/wow_mock.lua` is a small fake client. Frames accept any widget method and record state
  (`shown`, `text`, scripts), so UI code can run and be clicked through in tests.
- Write the test first, watch it fail, then make it pass (see CONTRIBUTING.md).
