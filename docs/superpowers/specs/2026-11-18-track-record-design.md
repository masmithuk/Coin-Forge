# Track record: suggestions vs what actually happened

## Why

Coin Forge suggests ways to make gold: deals to buy, prices to post at, crafts and conversions. Today
nobody can tell whether those suggestions really paid off. We want:

- **The player** to see, in the game, how well each kind of suggestion worked, so they know which ones
  to trust.
- **The developer** to get a detailed log from the SavedVariables file
  (`WTF\Account\<account>\SavedVariables\CoinForge.lua`) to tune the pricing maths.

## Goals

- Record every suggestion the player acts on: buying a deal, posting from the Sell tab. Link each one to
  what happened next: sold, at what price, the AH cut and deposit, or expired.
- An in-game **track record** per suggestion type: predicted vs actual profit, sell rate, how long items
  took to sell, and how far below the suggested price they sold.
- Keep the full log. Never delete it automatically.
- **Suggest** clearing when the log gets big or old, and give the player settings to clear it.

## Non-goals

- No data shared between players (solo data, as agreed earlier).
- No history from before this feature: it starts recording on install.
- Mob and node values aren't covered in v1. They're already averages of real loot. (My call:
  easy to add later as "predicted per kill vs this kill".)

## Anti-goals

- A log that silently makes `/reload` or logout slow, or the SavedVariables file huge, without the
  player ever being told.
- A track record that looks better than reality: items that never sell must count against it, not just
  disappear.
- Extra buttons the player has to press to make tracking work. It must be automatic.

## Constraints

- WoW Forever client (retail AH APIs, interface 16001). Event names must be validated before
  registering (`C_EventUtils.IsEventValid`).
- Only what happens while the addon is loaded can be seen. Sales are reported by a system message, and
  their proceeds arrive by mail invoice, possibly on another day or another character.
- Data is per market (`realm|faction` / `realm|Neutral`), like listings and deals.
- Pure logic goes in `src/Core` with busted tests. WoW glue goes in `src/WoW`, tested against the fake
  client.

## Approaches considered

1. **Rolling log only, with automatic expiry.** Simple, but it forgets history, and the player didn't want
   automatic deletion.
2. **Rolling log plus permanent totals, automatic expiry.** Compact long-term history, but still deletes
   things automatically.
3. **Totals only.** Tiny, but nothing to analyse when a number looks wrong.

**Chosen (by the player): keep the full log, and let the player clear it with prompts and settings.**
This is approach 2's structure without the automatic part. When the player clears entries, they're
folded into permanent weekly totals first, so the track record keeps its long-term numbers. (Folding
into totals on clear is my call.)

## Design

**Log entries** (`db.history[marketKey].entries`, oldest first):

- `buy`: item, quantity, unit price paid, the deal it came from (kind, predicted profit, predicted sell
  price), time.
- `post`: item, quantity, posted unit price, the price Coin Forge suggested, whether the player changed
  it, duration, deposit, time.
- `sold` / `expired` / `cancelled`: matched to the oldest open `post` of that item, oldest first. The
  `sold` amount is confirmed from the mail invoice when it's opened.
- A buy is paired with the later post and sale of that item, oldest first, to work out real flip profit.

**Linking a buy to a suggestion** (my call): when you buy an item that's in the current deals list, the buy is
tagged with that deal. Any other AH buy is logged as an untagged buy.

**Which deals get matched to an outcome in v1** (my call):

| Deal | Matched outcome |
|------|-----------------|
| Flips, From vendor | Buy, then AH sale of the same item |
| Vendor snipes | AH buy, then selling the item to a merchant |
| Sell tab posts | Post, then sale or expiry |
| Craft, disenchant, conversions | Not matched: the buy is logged and shown as "bought, predicted +X" |

Craft, disenchant and conversion deals change the item, so tracing them through is left for later.

**Rounds**:

- A round is buy → post(s) → sold.
- A round still open after N days (default 14; this only affects how it's reported, nothing is deleted)
  shows as **unsold** in the track record and counts as a loss at what was paid, minus deposits.
- If the item sells later, the round is corrected.

**Track record** (home screen section, plus `/cforge history`):

- One line per suggestion type, for example: "Flips: 12 rounds, predicted +3g 40s, actual +2g 10s,
  9 sold, 3 unsold".
- Sell tab: sell rate, average time to sell, average sale price vs suggestion.

**Totals** (`db.history[marketKey].weekly[yyyyww][kind]`):

- Counts and sums only.
- Clearing folds the cleared entries into these totals first, so the track record still covers
  everything.

**Keeping it tidy**:

- Settings (`/cforge config` and the options page):
  - "Suggest clearing after" a number of entries (default 2000).
  - "Suggest clearing after" an age (default 60 days).
  - "Clear history older than…": 30 days, 90 days or everything.
- When either limit is passed:
  - The home screen shows a one-line suggestion with a Clear button.
  - A chat line is printed once per session.
- `/cforge history clear [days]`.

## Left to the builder

- The exact events. Likely candidates: `AUCTION_HOUSE_PURCHASE_COMPLETED`, `COMMODITY_PURCHASE_SUCCEEDED`,
  `AUCTION_HOUSE_AUCTION_CREATED`, the `CHAT_MSG_SYSTEM` sold/expired messages, and
  `GetInboxInvoiceInfo` for proceeds. Check each one on Forever, and fall back gracefully.
- The matching details: partial commodity sales, and reposts after expiry.
- The layout of the home screen section, which should follow the existing style.
