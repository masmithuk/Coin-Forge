# Changelog

## 0.7.1 (2026-11-18)

- Fixed: items in the reagent bag slot (bag 5, where profession bags like a skinning bag can go) were
  missing from the Sell tab. Coin Forge now looks in every bag.
- New `/cforge bags` command shows what the Sell tab finds in each bag (slots, items, sellable), to help
  when something is missing.

## 0.7.0 (2026-11-18)

- **Track record.** Coin Forge now follows what you do with its suggestions and shows how each kind
  really did, on the home screen and with `/cforge history`. For example: "Flip: 12 done, predicted
  +3g 40s, actual +2g 10s (9 sold, 3 unsold)", or "Sell tab: 20 posts, 75% sold at 96% of the
  suggestion".
  - Flip, From vendor and Other AH buys are followed to their AH sale, and vendor deals to the merchant.
    Sell tab posts are followed until they sell or expire.
  - Items unsold after 14 days count as a loss until they sell.
- **The log is never deleted automatically.** Once it reaches 2000 entries or 60 days old, the home screen
  shows a hint with a Clear button, and chat reminds you once per login.
  - Use `/cforge history clear [days]` to clear it yourself.
  - Clearing keeps the totals.
  - The limits are settings: `historyTidyEntries`, `historyTidyDays` and `unsoldDays`.
- Fixed: two parts of the addon listening to the same game event could silently replace each other's
  handler. Both now run.

## 0.6.1 (2026-11-18)

- Fixed: a scan could stay on "Scanning..." forever. It now gives up with a reason in the panel and in chat:
  - when the server sends no scan data within 90 seconds;
  - when the auction house is closed before the data arrives;
  - when reading the results fails.

  If no data arrived, the 15-minute wait is handed back, so you can press Scan again straight away.

## 0.6.0 (2026-11-17)

- **Gathering stats.** Mining veins and herbs you gather are learned like mobs: hover a node to see its
  value **per gather** and what it yields (Copper Ore x2.3, Malachite 6%...). The home screen lists your
  **Best to gather** nodes.
- **Skinning per corpse** is now shown separately in mob tooltips, below the loot per kill. A mob's value
  on nameplates and in Best mobs includes skinning only for characters who can skin.
- Skinning is recognised from the Skinning cast itself, so it no longer depends on looting order; an
  interrupted or failed cast is forgotten. Chests and quest objects you didn't gather are ignored.

## 0.5.1 (2026-11-17)

- Fixed: the 15-minute scan cooldown was shared by every character on the account, so scanning on a PvE
  character locked Scan on your PvP characters. It's now per realm (each WoW Forever ruleset is its own
  realm).
- Fixed: the last scan's listings and the home screen's best deals were shared too, so a PvP character could
  be shown the PvE auction house's deals (and the neutral AH showed the faction AH's). They're now kept per
  auction house and swapped in when you open a different one.
- Mob loot, recipes and vendor prices stay shared by all your characters, since they're the same everywhere.

## 0.5.0 (2026-11-17)

- Item tooltips show **Turn into**: everything the item can be crafted or converted into with a single
  ingredient (Tin Ore into Tin Bar, 2 Linen Cloth into a bandage, essence combining and splitting...),
  valued per item you start with at today's prices after the AH cut. Green means better than selling it as
  it is, red means worse. Recipes known only by another character show that character's name.
- Releases: publishing a GitHub release (any tag style, `0.5.0` or `v0.5.0`) now builds and uploads to
  CurseForge; re-running a failed release is safe.
- Sell tab: recommends **Craft first** when a recipe this character knows makes the item worth more than
  posting, vendoring or disenchanting it, and says by how much.

## 0.4.0 (2026-11-16)

First public release on CurseForge, for WoW Forever (1.60.1).

- **Renamed from ForeverGold to Coin Forge**, because other addons called ForeverGold already exist. The slash
  command is now `/cforge` (or `/coinforge`), and the folder, title and saved data are named CoinForge.

- AH scanning with price history per auction house, kept fresh by your own searches.
- Deals: flips, vendor snipes, From vendor, essence conversions, disenchanting, crafts and other-AH arbitrage.
- Sell tab with trap-aware pricing (ignores bait and price wars, never undercuts you) and one-click posting.
- Crafting profit and loss, a Conversions view, profitable-mob nameplates, vendor highlights, smart tooltips.
- New `/cforge recipes` command shows what the recipe recorder sees in an open profession window.

Known issue: recipes recorded by earlier versions may still show as learned when they aren't. Opening the
profession window corrects them in most cases. Please report `/cforge recipes` output if it doesn't.

## 0.3.6 (2026-11-16)

- Fixed: after a `/reload`, Deals was empty (the listings only lived in memory) while Scan was locked by the
  15-minute cooldown. The last scan's listings are now saved (each item's 20 cheapest price levels), so deals
  come straight back. Listings older than a day aren't restored.
- An empty Deals list no longer says "Press Scan" when Scan is locked: it shows when Scan unlocks and points
  out that searching an item still updates its prices.

## 0.3.5 (2026-11-16)

- Fixed: every recipe in a profession was recorded as known, including unlearned ones (WoW Forever's recipe
  list includes them), so crafting showed recipes far above your skill. Only learned recipes count now.
  Re-open each profession window once to correct recipes recorded by older versions.
- New **Show unlearned** checkbox on the Crafting view lists recipes none of your characters have learned,
  with their profit, so you can see what's worth learning. Off by default.
- Craft deals only use recipes one of your characters has learned.

## 0.3.4 (2026-11-16)

- Disenchant estimates price materials at their latest AH price (last scan or search, up to a day old), so
  they match what a search shows. Older data falls back to the 14-day market value.
- Sell tab: characters who can disenchant an item are told to **Disenchant** it when the materials are worth
  more than posting or vendoring, with the numbers.

## 0.3.3 (2026-11-16)

- Fixed: professions were never detected on WoW Forever, which replaced the old skill functions with
  `C_SkillInfo`. Disenchant values and deals, and the "Only what I can do" filter, now see your real skills.
- Item tooltips show a disenchant estimate for characters with Enchanting: expected value after the AH cut,
  the likely materials with their chances and prices, and the skill needed if yours is too low.
- New `/cforge skills` command shows the professions Coin Forge has detected.
- Fixed: clicking 2 h / 8 h / 24 h didn't move the highlight, so 8 h always looked selected (the chosen
  duration was used, it just wasn't shown). Every tab bar now highlights a click immediately.

## 0.3.2 (2026-11-15)

- Searching an item anywhere (Blizzard's Buy tab, a deal row, or the Sell tab) now updates its price data and
  its listings in the deal list, so prices stay current between full scans.
- The Sell tab loads every page of an item's results before pricing it, so the price list shows all
  current postings.

## 0.3.1 (2026-11-15)

- Fixed: Post could stay greyed out after selecting an item. The live price check keeps the AH busy for a
  moment, and nothing re-enabled the button afterwards. It now turns back on by itself.
- Post is never disabled without a visible reason (status line and button tooltip).
- New price list under the sell inputs: every listing with what the pricing made of it, plus where your
  price sits, so you can check the maths.

## 0.3.0 (2026-11-15)

- New Sell tab, like Auctionator's selling page: every sellable bag item with a suggested price. Click one and
  price, quantity and duration are set up (all editable), then one click on Post. It moves on to the next item.
- Trap-aware pricing: ignores bait listings, refuses to follow price wars below 60% of normal, never undercuts
  your own auctions, and recommends vendoring when the AH pays less.
- Live search when you pick an item, so prices are current and your own listings are recognised.
- Gear is posted buyout-only, so it can't be won with a low bid.
- New settings: `undercut`, `sellFloor`, `baitShare`, `sellDuration`.

## 0.2.0 (2026-11-15)

- Fixed: the addon didn't load on WoW Forever (it registered a Classic-only event).
- New Conversions view: every essence combine/split with live profit or loss.
- New "From vendor" deals: items a vendor you've visited sells for less than the AH pays, with where to buy them.
- Disenchant deals are hidden for characters without Enchanting.
- Fixed: vendor snipes and disenchant deals were missed for items the client hadn't loaded yet; deals now
  update as item data arrives after a scan.
- The "Only what I can do" toggle now says what it's hiding.

## 0.1.0 (2026-11-15)

First release for WoW Forever (interface 16001).

- Manual full auction house scan with daily price history per market (faction and neutral AHs kept apart).
- Deals panel docked beside the auction house: flips, vendor snipes, disenchanting, essence conversions,
  crafts, "make it yourself" and other-AH arbitrage, with an "Only what I can do" filter.
- Crafting view: profit or loss of every recipe your characters know.
- Profitable mob coins on nameplates and loot-per-kill in mob tooltips, learned from your own loot.
- Vendor items worth more on the AH glow green in the merchant window.
- Item tooltips with AH value, vendor, disenchant value and the best action.
- Home screen, minimap button and addon-compartment entry that explain the addon.
- Farming session tracker (gold per hour) and `/cforge` commands.
