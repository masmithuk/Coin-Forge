# Changelog

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
