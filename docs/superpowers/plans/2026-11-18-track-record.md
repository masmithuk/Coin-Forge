# Track Record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Log what the player does with Coin Forge's suggestions (AH buys, vendor buys/sales, Sell-tab posts) and what happened (sold, expired), and show predicted vs actual per suggestion type, with prompts and settings to clear the log.

**Architecture:** A pure `History` core module owns the log, the matching of buys/posts to outcomes ("rounds"), weekly totals and clearing. A `TradeRecorder` WoW adapter turns client events and hooks into `History` calls. App/Main/HomeScreen/Commands expose it.

**Tech Stack:** Lua 5.1 (WoW), busted, luacheck. Existing fake client `spec/helpers/wow_mock.lua`.

**Spec:** `docs/superpowers/specs/2026-11-18-track-record-design.md`

## Global Constraints

- Never delete log entries automatically; only on the player's clear.
- Clearing folds cleared rounds into `weekly` totals first.
- Per market key (`realm|faction` / `realm|Neutral`): `db.history[marketKey] = { entries = {}, weekly = {} }`.
- Defaults: suggest clearing at 2000 entries or oldest entry 60 days; unsold after 14 days; clear choices 30 / 90 days / everything.
- Validate every event name before registering (existing `on()` in Main.lua does this); every hook guarded by existence checks.
- Unsold rounds count as a loss at cost (plus deposits); corrected if the item sells later.

## Review Focus

- A sale message for an item with no logged post (posted before install or by another addon) → ignored, no error.
- Partial commodity sales (sold 5 of a 20 post) → that post round stays open for the rest.
- Same item bought from a flip and also posted from the Sell tab → sales go FIFO to the oldest open post; buys pair FIFO with sales of that item.
- Clearing while rounds are still open and young → those entries stay.
- `/reload` mid-round → state lives only in saved entries; nothing in memory is needed to finish a round.

---

### Task 1: History core (log, rounds, summary, clear)

**Files:**
- Create: `src/Core/History.lua` (add to `CoinForge.toc` after `GatherDB.lua`)
- Test: `spec/core/history_spec.lua`

**Interfaces:**
- Produces:
  - `History.new(db, clock)`; `h:market(key)` → book with:
    - `book:buy(itemID, qty, unitPrice, deal)` — `deal` = `{ kind, profit, qty }` or nil (untagged)
    - `book:post(itemID, qty, unitPrice, suggested, deposit)` — `suggested` = suggested unit price or nil
    - `book:sold(itemID, qty, net)` — `net` total proceeds or nil (estimated from the post: price×qty×(1−cut))
    - `book:expired(itemID, qty)`
    - `book:vendorSale(itemID, qty, unitPrice)`
    - `book:rounds(opts)` → list of `{ kind, start, predicted, actual, status = "sold"|"unsold"|"open"|"logged", itemID }`; `opts = { unsoldDays = 14, cut = 0.05 }`
    - `book:summary(opts)` → `{ [kind] = { rounds, sold, unsold, open, predicted, actual } }` live rounds plus weekly totals; Sell-tab posts use kind `"sell"` and add `sellRate`, `avgDiscount` (avg posted/suggested)
    - `book:clear(olderThanDays, opts)` → number of entries removed (nil days = everything); folds closed rounds started before the cutoff into `weekly[yyyyww][kind]`; keeps entries of open rounds younger than `unsoldDays`
    - `book:tidyAdvice(limits)` → nil or `{ entries, oldestDays }` when `#entries >= limits.entries` or oldest `>= limits.days`

Matching (FIFO by itemID, oldest first):
- `sold`/`expired` consume open quantity of the oldest posts of that item.
- Tagged buys of kind `flip`, `vendorFlip`, `arbitrage` pair with that item's `sold` quantity; kind `vendor` pairs with `vendorSale`. Actual = net received for the paired qty − unit cost × qty − deposits of posts of that item within the round.
- Buys of other kinds → status `"logged"`, predicted only.

- [ ] **Step 1: Write failing tests**: `it("a flip bought then sold shows predicted vs actual")` (buy 2 @100 deal profit 150, post 2 @200 deposit 10, sold 2 net 380 → actual 380−200−10=170, predicted 150, status sold); `it("an unsold flip counts as a loss after 14 days")` (actual −200, status unsold; then sold later → sold); `it("matches sales FIFO across partial commodity sales")`; `it("sell-tab posts report sell rate and discount vs suggestion")`; `it("vendor snipes pair with vendor sales")`; `it("ignores sales with no logged post")`; `it("clear folds closed rounds into weekly totals and keeps young open ones")` (summary identical before/after clear); `it("suggests tidying at 2000 entries or 60 days")`.
- [ ] **Step 2:** `busted spec/core/history_spec.lua` → FAIL (module missing).
- [ ] **Step 3:** Implement `src/Core/History.lua`.
- [ ] **Step 4:** `busted` → all pass; `luacheck . -q` → 0 warnings.
- [ ] **Step 5:** Commit `feat: history log with rounds, summary and clearing`.

### Task 2: Settings and TradeRecorder adapter

**Files:**
- Modify: `src/Core/Settings.lua` — add `historyTidyEntries = 2000 (number)`, `historyTidyDays = 60 (number)`, `unsoldDays = 14 (number)`.
- Create: `src/WoW/TradeRecorder.lua` (toc after `LootRecorder.lua`)
- Test: `spec/wow/adapters_spec.lua` ("TradeRecorder" describe)

**Interfaces:**
- Consumes: Task 1 book methods.
- Produces: `TradeRecorder.new(deps)` with `deps = { book = fn() -> book, dealFor = fn(itemID, kinds) -> deal|nil, cut = fn() -> ratio }`; `rec:onEvent(event, ...)`; `rec:install()` (hooks).
  - AH commodity buy: hook `C_AuctionHouse.StartCommoditiesPurchase(itemID, qty)`, remember `COMMODITY_PRICE_UPDATED(unitPrice)`, record on `COMMODITY_PURCHASE_SUCCEEDED`.
  - AH item buy: map auctionID → itemID/buyout from `ITEM_SEARCH_RESULTS_UPDATED` via `C_AuctionHouse.GetItemSearchResultInfo`; hook `C_AuctionHouse.PlaceBid(auctionID, bid)`; record on `AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)`.
  - Tag with `dealFor(itemID, {"flip","vendor","arbitrage","disenchant","conversion","craft","craftInstead"})`.
  - Vendor buy: hook `BuyMerchantItem(index, qty)`; price from `GetMerchantItemInfo`; tag `dealFor(itemID, {"vendorFlip"})`.
  - Vendor sale: hook `C_Container.UseContainerItem(bag, slot)` while `MerchantFrame:IsShown()`; record `vendorSale` with the item's vendor price.
  - Sold/expired: `CHAT_MSG_SYSTEM` matched against patterns built from `ERR_AUCTION_SOLD_S` / `ERR_AUCTION_EXPIRED_S` (format `%s` → capture); item name → itemID via the book's open posts.
- [ ] **Step 1: Failing tests**: commodity purchase recorded with deal tag; item purchase via PlaceBid recorded; buy not in deals is untagged; sold/expired system messages reach the book; vendor buy and vendor sale recorded only with merchant open; unknown sold item name ignored.
- [ ] **Step 2:** run → FAIL. **Step 3:** implement (add fake-client functions to `wow_mock.lua` as needed). **Step 4:** `busted` + `luacheck` clean. **Step 5:** commit `feat: record AH and vendor trades into history`.

### Task 3: App, posting hook, UI, commands, docs, release

**Files:**
- Modify: `src/WoW/App.lua` — `app.history = ns.History.new(saved, clock)`; `App:book()` (current market); `App:dealFor(itemID, kinds)` (best `lastOpportunities` match); `App:trackRecord()` → `book:summary{unsoldDays, cut}`; `App:tidyAdvice()`; `App:clearHistory(days)`.
- Modify: `src/UI/SellView.lua` — after a successful `Poster.post`, `app:book():post(itemID, qty, price, suggestion.price, deposit)`.
- Modify: `Main.lua` — create/install TradeRecorder, register its events, `/cforge history` (prints summary lines) and `/cforge history clear [days]`; once-per-session chat suggestion on login when `tidyAdvice()`.
- Modify: `src/UI/HomeScreen.lua` — "Track record" section: one line per kind with data ("Flip: 12 rounds, predicted +3g 40s, actual +2g 10s, 9 sold, 3 unsold"; sell: "Sell tab: 20 posts, 75% sold, sold at 96% of suggestion"); tidy line + "Clear older than 30 days" button when advice present.
- Modify: `src/Core/HomeModel.lua` features list; `README.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md` 0.7.0; version to 0.7.0 in toc + Namespace.
- Test: `spec/wow/app_spec.lua` (trackRecord, dealFor, clear), UI smoke spec still passing.
- [ ] Steps: failing app tests → implement → `busted` + `luacheck` → commit `Coin Forge 0.7.0: track record` → push main → copy changed game files to `F:\World of Warcraft\_forever_\Interface\AddOns\CoinForge`.
