# Coin Forge

**A gold-making companion for World of Warcraft: Forever.**
It learns prices from your own auction house scans, then points out money
wherever you are: at the auctioneer, at vendors and out in the world.

*Coin Forge was called ForeverGold before version 0.4.0. It was renamed because other addons already use that
name; the slash command is now `/cforge`.*

---

## What it does

| Where | What you see |
| --- | --- |
| **Auction house** | A Coin Forge panel docked beside the AH with one **Scan** button and a list of deals, best first: flips, vendor snipes, disenchanting, essence conversions, crafts, "make it yourself" and other-AH arbitrage. Click a row and it's searched in the Blizzard Buy tab next to it. |
| **Crafting** | Profit or loss of every recipe your characters have learned, at today's prices. Tick **Show unlearned** to also see recipes nobody has learned yet (usually ones above your skill) and whether they'd be worth learning. |
| **Selling** | A Sell tab listing everything in your bags you can auction, most valuable first. Click one: price, quantity and duration are set up for you (all editable), then one click on **Post**. |
| **Conversions** | Every essence combine (3 lesser → 1 greater) and split (1 greater → 3 lesser), with live profit or loss. No profession needed. |
| **Out in the world** | A coin and value over nameplates of mobs worth farming, plus "loot per kill", "skinning per corpse" and best drops in the mob's tooltip. Veins and herbs show their value per gather and yields. |
| **Vendors** | Items a vendor sells for less than the AH pays glow green, with the profit shown underneath. |
| **Item tooltips** | AH value, lowest listing, vendor price and the **best thing to do** with the item. **Turn into** shows what it can be crafted or converted into with a single ingredient (ore into bars, cloth into bandages, essences), valued per item, with the gain or loss in green or red. Characters with Enchanting also see a disenchant estimate with the likely materials at their latest AH price (from your last scan or search), and the skill needed if yours is too low. |
| **Home screen** | Opened from the minimap coin or `/cforge`: status, a getting-started checklist, best deals, best mobs, best nodes to gather, gold per hour and a short guide. |

Coin Forge never buys, posts or clicks for you. Every purchase goes through Blizzard's own UI.

## Install

**From CurseForge:** install Coin Forge with the CurseForge app (choose the WoW Forever flavor), or download the
zip from the project page and extract it into your WoW Forever `Interface/AddOns` folder.

**From source:**

1. Download or clone this repository.
2. Put the folder in the `Interface/AddOns/` folder of your **WoW Forever** game folder (inside your World of
   Warcraft install, next to the retail and classic ones). Make sure it is named **`CoinForge`**, so the path
   ends in `AddOns/CoinForge/CoinForge.toc`.
3. Restart the game client completely. WoW only discovers new addons at launch.

The development files (`spec/`, `docs/`) are ignored by the game, so you can install the repo as it is.

## Quick start

1. **Scan.** Open any auction house and press **Scan** on the Coin Forge panel. A full scan takes a few seconds,
   and the server allows one every 15 minutes.
2. **Come back on another day.** Deals need at least 2 days of prices before they're trusted (you can change this).
   Tooltips and crafting values work straight away.
3. **Open each profession window once** on each character. Coin Forge records the recipes, so crafting
   profit and "make it yourself" suggestions cover all your alts.
4. **Just play.** Every mob you loot teaches Coin Forge what that kind of mob drops. After 5 kills
   (configurable), profitable ones get a coin on their nameplate.

The minimap coin's tooltip and the home screen explain all of this in game as well.

## How the numbers work

- **Market value** is the median of the last 14 days' prices. Each day's price is the 20th-percentile unit
  price of that day's scan, so one silly listing can't distort it.
- **Profit is always after the AH cut**: 5% on faction auction houses, 15% on the neutral ones (Booty Bay,
  Gadgetzan, Everlook). Deposits are ignored because they're refunded when an item sells.
- **Searches keep prices fresh.** Whenever you search an item (in Blizzard's Buy tab, by clicking a deal, or
  by picking it in the Sell tab), all its current listings become today's price for it, and the deal list
  updates. You don't need a full scan for one item.
- **Each auction house is its own market, and so is each realm.** On WoW Forever every ruleset (PvE, PvP...)
  is its own realm, so PvE and PvP characters never share prices, deals or the 15-minute scan cooldown.
  Mob loot, recipes and vendor prices are shared by all your characters.
- **Faction and neutral auction houses are separate too.** Prices from the Horde, Alliance and Neutral AHs are kept apart,
  and that separation is what makes arbitrage deals possible.
- **Disenchant values** use the classic disenchanting tables (`src/Data/Disenchant.lua`). If WoW Forever changes
  them, that's the one file to edit.
- **Mob values** are `(coin + Σ drops × best value) ÷ kills`, from your own loot across all your characters.
  Skinning is kept separately per corpse skinned, and only added to a mob's value if you can skin.
- **Node values** are `Σ yields × best value ÷ gathers` for each vein or herb, by name, learned from your
  Mining and Herb Gathering casts.

## Deal types

| Tab | Meaning | Who can do it |
| --- | --- | --- |
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

Open the **Sell** tab on the Coin Forge panel at any auction house.

1. Your sellable bag items are listed with a suggested price each and the advice: **Post**, **Vendor it**
   (the AH pays less than a vendor after the cut) or **Set a price** (no data yet).
2. Click an item. The suggestion fills in from your last scan, then a live search updates it with current
   prices, including which listings are yours.
3. Change the price (type `1g 20s`, `85s` or plain copper), the quantity or the duration (2 h / 8 h / 24 h)
   if you like. The total, what you'll get after the cut, and the deposit update as you type.
4. Check the maths in the **price list** under the inputs: every listing on the AH with what Coin Forge made of
   it (*bait, ignored*, *price war, ignored*, *your auction*, *cheapest real listing: undercut by 1c*), with
   **your price** shown where your auction would sit. The line above it gives the normal price and the floor.
5. Press **Post** (or Enter). Coin Forge moves on to the next item. If Post is greyed out, the line under the
   inputs (and the button's tooltip) says why. When the AH is briefly busy after a price check, it turns
   back on by itself.

### How the price is chosen (and the traps it avoids)

| Situation | What Coin Forge does |
| --- | --- |
| Your own auction is the cheapest | Matches it, never undercutting yourself |
| A few listings far under the normal price (**bait**) | Ignores them. They're there to make you undercut and crash the price |
| A big wall of cheap listings, and the item has price history (**price war**) | Won't follow it down. Sits just under the cheapest sensible listing, or at the floor |
| Normal competition | Undercuts the cheapest listing by `undercut` (1c by default) |
| Nobody else selling | Posts at the item's normal market value |
| The AH pays less than a vendor after the cut | Recommends vendoring instead |
| You can disenchant it and the materials are worth more than posting or vendoring | Recommends **Disenchant** (the posting price is still filled in if you'd rather post) |
| You know a recipe that turns it into something worth more (e.g. smelting ore into bars) | Recommends **Craft first** and names the item to make |

"Far under" means below `sellFloor` (60%) of the normal price. "A few" means at most `baitShare` (20%)
of the units listed. Gear is posted buyout-only, so nobody can win it with a low starting bid.

## Commands

| Command | Does |
| --- | --- |
| `/cforge` | Open or close the home screen |
| `/cforge mobs` | List the 10 best mobs you've farmed |
| `/cforge reset` | Start a new farming session |
| `/cforge skills` | Show the professions Coin Forge has detected on this character |
| `/cforge minimap` | Show or hide the minimap coin |
| `/cforge config` | List settings with their current values |
| `/cforge config <name> <value>` | Change a setting, e.g. `/cforge config minProfit 1g 50s` or `/cforge config flipDiscount 25%` |

### Settings

| Name | Default | Meaning |
| --- | --- | --- |
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
- [docs/RELEASING.md](docs/RELEASING.md): how to publish a new version to GitHub and CurseForge
- [docs/superpowers/specs/2026-11-15-coinforge-design.md](docs/superpowers/specs/2026-11-15-coinforge-design.md): the original design

## Licence

MIT. See [LICENSE](LICENSE).
