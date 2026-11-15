# ForeverGold

**A gold-making companion for World of Warcraft: Forever.**
It learns prices from your own auction house scans, then points out money
wherever you are: at the auctioneer, at vendors and out in the world.

---

## What it does

| Where | What you see |
|---|---|
| **Auction house** | A ForeverGold panel docked beside the AH with one **Scan** button and a list of deals, best first: flips, vendor snipes, disenchanting, essence conversions, crafts, "make it yourself" and other-AH arbitrage. Click a row and it's searched in the Blizzard Buy tab next to it. |
| **Crafting** | Profit or loss of every recipe your characters know, at today's prices. |
| **Selling** | A Sell tab listing everything in your bags you can auction, most valuable first. Click one: price, quantity and duration are set up for you (all editable), then one click on **Post**. |
| **Conversions** | Every essence combine (3 lesser → 1 greater) and split (1 greater → 3 lesser), with live profit or loss. No profession needed. |
| **Out in the world** | A coin and value over nameplates of mobs worth farming, plus "loot per kill" and best drops in the mob's tooltip. |
| **Vendors** | Items a vendor sells for less than the AH pays glow green, with the profit shown underneath. |
| **Item tooltips** | AH value, lowest listing, vendor price, disenchant value and the **best thing to do** with the item. |
| **Home screen** | Opened from the minimap coin or `/fg`: status, a getting-started checklist, best deals, best mobs, gold per hour and a short guide. |

ForeverGold never buys, posts or clicks for you. Every purchase goes through Blizzard's own UI.

## Install

1. Download or clone this repository.
2. Put the folder in the `Interface/AddOns/` folder of your **WoW Forever** game folder (inside your World of
   Warcraft install, next to the retail and classic ones). Make sure it is named **`ForeverGold`**, so the path
   ends in `AddOns/ForeverGold/ForeverGold.toc`.
3. Restart the game client completely. WoW only discovers new addons at launch.

The development files (`spec/`, `docs/`) are ignored by the game, so you can install the repo as it is.

## Quick start

1. **Scan.** Open any auction house and press **Scan** on the ForeverGold panel. A full scan takes a few seconds,
   and the server allows one every 15 minutes.
2. **Come back on another day.** Deals need at least 2 days of prices before they're trusted (you can change this).
   Tooltips and crafting values work straight away.
3. **Open each profession window once** on each character. ForeverGold records the recipes, so crafting
   profit and "make it yourself" suggestions cover all your alts.
4. **Just play.** Every mob you loot teaches ForeverGold what that kind of mob drops. After 5 kills
   (configurable), profitable ones get a coin on their nameplate.

The minimap coin's tooltip and the home screen explain all of this in game as well.

## How the numbers work

- **Market value** is the median of the last 14 days' prices. Each day's price is the 20th-percentile unit
  price of that day's scan, so one silly listing can't distort it.
- **Profit is always after the AH cut**: 5% on faction auction houses, 15% on the neutral ones (Booty Bay,
  Gadgetzan, Everlook). Deposits are ignored because they're refunded when an item sells.
- **Each auction house is its own market.** Prices from the Horde, Alliance and Neutral AHs are kept apart,
  and that separation is what makes arbitrage deals possible.
- **Disenchant values** use the classic disenchanting tables (`src/Data/Disenchant.lua`). If WoW Forever changes
  them, that's the one file to edit.
- **Mob values** are `(coin + Σ drops × best value) ÷ kills`, from your own loot across all your characters.
  Skinning a corpse adds its leather to that mob without counting a second kill.

## Deal types

| Tab | Meaning | Who can do it |
|---|---|---|
| Flip | Listed at least 30% under market value. Buy it and relist. | Everyone |
| Vendor | Listed below what any vendor pays for it. Buy it on the AH, sell it to any vendor. | Everyone |
| From vendor | A vendor you've visited sells it for less than the AH pays. Shows the vendor's name and zone. | Everyone |
| Disenchant | Worth more as enchanting materials. Hidden for characters without Enchanting. | Enchanters with enough skill |
| Convert | Combine 3 lesser essences into 1 greater (or split one), for profit. | Everyone |
| Craft | Buy the reagents now, craft, and sell the result. | Characters who know the recipe |
| Make it | Listed for more than it costs you to craft. | Characters who know the recipe |
| Other AH | Sells for more on another auction house after its cut. | Everyone (carry it there) |

Tick **Only what I can do** to hide anything your current character can't do.

## Selling

Open the **Sell** tab on the ForeverGold panel at any auction house.

1. Your sellable bag items are listed with a suggested price each and the advice: **Post**, **Vendor it**
   (the AH pays less than a vendor after the cut) or **Set a price** (no data yet).
2. Click an item. The suggestion fills in from your last scan, then a live search updates it with current
   prices, including which listings are yours.
3. Change the price (type `1g 20s`, `85s` or plain copper), the quantity or the duration (2 h / 8 h / 24 h)
   if you like. The total, what you'll get after the cut, and the deposit update as you type.
4. Press **Post** (or Enter). ForeverGold moves on to the next item.

### How the price is chosen (and the traps it avoids)

| Situation | What ForeverGold does |
|---|---|
| Your own auction is the cheapest | Matches it, never undercutting yourself |
| A few listings far under the normal price (**bait**) | Ignores them. They're there to make you undercut and crash the price |
| A big wall of cheap listings, and the item has price history (**price war**) | Won't follow it down. Sits just under the cheapest sensible listing, or at the floor |
| Normal competition | Undercuts the cheapest listing by `undercut` (1c by default) |
| Nobody else selling | Posts at the item's normal market value |
| The AH pays less than a vendor after the cut | Recommends vendoring instead |

"Far under" means below `sellFloor` (60%) of the normal price. "A few" means at most `baitShare` (20%)
of the units listed. Gear is posted buyout-only, so nobody can win it with a low starting bid.

## Commands

| Command | Does |
|---|---|
| `/fg` | Open or close the home screen |
| `/fg mobs` | List the 10 best mobs you've farmed |
| `/fg reset` | Start a new farming session |
| `/fg minimap` | Show or hide the minimap coin |
| `/fg config` | List settings with their current values |
| `/fg config <name> <value>` | Change a setting, e.g. `/fg config minProfit 1g 50s` or `/fg config flipDiscount 25%` |

### Settings

| Name | Default | Meaning |
|---|---|---|
| `minProfit` | 50s | Minimum total profit for a deal to be listed |
| `flipDiscount` | 30% | How far under market value a listing must be to count as a flip |
| `minHistoryDays` | 2 | Days of price history needed before a value is trusted |
| `mobMinValue` | 50s | Loot value per kill needed for a nameplate coin |
| `mobMinKills` | 5 | Kills recorded before a mob's value is trusted |
| `historyDays` | 30 | Days of price snapshots kept |
| `undercut` | 1c | How much to undercut the cheapest competitor by |
| `sellFloor` | 60% | Never follow prices below this share of the normal price |
| `baitShare` | 20% | Cheap listings that are at most this share of supply count as bait |
| `sellDuration` | 2 | Default auction length: 1 = 2 h, 2 = 8 h, 3 = 24 h (the tab remembers your last choice) |
| `showNameplates`, `showTooltips`, `showMerchant`, `showMinimap` | on | Turn individual features on or off |

## Known limitations

- **English client names.** Profession names and the neutral-town names are matched in English (enUS/enGB).
- **Item variants.** Items with random suffixes ("of the Bear", for example) share one price per item.
- **Collapsed profession categories** in the classic profession window hide their recipes from the recorder.
  Expand them once to record everything.
- **Brand-new game version.** WoW Forever launched on 4 November 2026. Every API call is feature-checked,
  so if Blizzard changes something, that one feature switches off rather than the whole addon breaking.
  Please open an issue with the Lua error if you hit one.

## For developers

The logic is plain Lua tested outside the game with [busted](https://lunarmodules.github.io/busted/).
WoW-specific code is a thin layer on top.

```sh
busted        # 120+ tests, under a second
luacheck .    # lint
```

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the pieces fit together, how data is stored, and how to add a new kind of deal
- [CONTRIBUTING.md](CONTRIBUTING.md): the test-first workflow and code conventions
- [docs/superpowers/specs/2026-11-15-forevergold-design.md](docs/superpowers/specs/2026-11-15-forevergold-design.md): the original design

## Licence

MIT. See [LICENSE](LICENSE).
