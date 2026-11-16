# Changelog

## 0.4.0 (2026-11-16)

First public release on CurseForge, for WoW Forever (1.60.1).

- AH scanning with price history per auction house, kept fresh by your own searches.
- Deals: flips, vendor snipes, From vendor, essence conversions, disenchanting, crafts and other-AH arbitrage.
- Sell tab with trap-aware pricing (ignores bait and price wars, never undercuts you) and one-click posting.
- Crafting profit and loss, a Conversions view, profitable-mob nameplates, vendor highlights, smart tooltips.
- New `/fg recipes` command shows what the recipe recorder sees in an open profession window.

Known issue: recipes recorded by earlier versions may still show as learned when they aren't. Opening the
profession window corrects them in most cases. Please report `/fg recipes` output if it doesn't.

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
- New `/fg skills` command shows the professions ForeverGold has detected.
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
- Farming session tracker (gold per hour) and `/fg` commands.
