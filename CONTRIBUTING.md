# Contributing

Thanks for helping. This project is built test-first, so the workflow below matters more than anything else here.

## Setup

You need Lua 5.1 (WoW's dialect), [busted](https://lunarmodules.github.io/busted/) and
[luacheck](https://github.com/lunarmodules/luacheck).

```sh
# Ubuntu / Debian
sudo apt-get install lua5.1 luarocks lua-busted
sudo luarocks --lua-version 5.1 install luacheck

# macOS
brew install lua@5.1 luarocks && luarocks --lua-version 5.1 install busted luacheck
```

Then, from the repository root:

```sh
busted       # run every test
luacheck .   # lint
```

CI runs both on every push and pull request.

## Test-first workflow

1. **Write a failing test** that describes the behaviour, in `spec/core/` for logic or `spec/wow/` for adapters/UI.
2. **Run it and watch it fail** for the reason you expect. A test that passes straight away isn't testing anything new.
3. **Write the smallest code** that makes it pass.
4. **Refactor** with the tests green.
5. Run `busted && luacheck .` before you push.

For bugs: write a test that reproduces the bug first, then fix it.

## Where code goes

| If it... | Put it in | Test it in |
|---|---|---|
| decides, calculates or formats | `src/Core/` (no WoW globals allowed) | `spec/core/` |
| calls the WoW API | `src/WoW/`, small, translating to plain tables | `spec/wow/adapters_spec.lua` with `wow_mock` |
| creates frames | `src/UI/`, with its logic moved into a Core model | `spec/wow/ui_smoke_spec.lua` |
| is static game data | `src/Data/` | via the module that reads it |

Every new file must be added to `ForeverGold.toc` **in load order**. The test loader reads the `.toc`,
so a missing entry fails the tests.

## Conventions

- Each file starts with `local _, ns = ...` and registers one module: `ns.ModuleName = ModuleName`.
- Money is always **integer copper**. Format it only at the edge, with `ns.Money`.
- Prefer pure functions over plain tables. Pass dependencies in (`ctx`, `deps`) rather than reading globals.
- Feature-detect WoW APIs (`ns.Api.has`) so a missing API disables one feature, not the addon.
- No automation of purchases or posting: Blizzard requires a hardware click, and we respect that.
- A short comment at the top of each file says what it's for, and functions get a `---` doc line
  when their arguments aren't obvious.
- Lines stay under 120 characters (luacheck enforces it).

## UI changes

Read the *UI principles* in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#ui-principles). In short:
don't add a button if a click on content or a tab can do the job, give every empty state a next step,
and check the window at its minimum size.
