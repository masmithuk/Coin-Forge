# Releasing

A release is one GitHub release. Publishing it starts `.github/workflows/release.yml`, which:

1. lints and runs the tests,
2. builds `dist/CoinForge-<version>.zip` with `scripts/package.sh` (only the files the game needs),
3. attaches the zip to the release (and fills in empty release notes from `CHANGELOG.md`),
4. uploads the zip to CurseForge as a **WoW Forever (1.60.1)** file with `scripts/upload-curseforge.sh`.

## One-time setup

1. **Create the CurseForge project** at <https://authors.curseforge.com> (World of Warcraft > Addons), with
   category *Auction & Economy* and the description from [CURSEFORGE.md](CURSEFORGE.md). New projects are
   reviewed by CurseForge moderators before they go public.
2. **Note the project id**, shown under "About This Project" on the project's overview page.
3. **Create an API token** at <https://www.curseforge.com/account/api-tokens>.
4. In the GitHub repo, open **Settings > Secrets and variables > Actions** and add:
   - secret **`CF_API_KEY`**: the API token
   - variable **`CF_PROJECT_ID`**: the project id

## Each release

1. Update `## Version:` in `CoinForge.toc`, `ns.version` in `src/Core/Namespace.lua`, and add a
   `## x.y.z (date)` entry at the top of `CHANGELOG.md`. Commit and push to `main`.
2. On GitHub, go to **Releases > Draft a new release**, create a tag with the same version (`0.5.0` or
   `v0.5.0`, either works) on `main`, and click **Publish release**.

The workflow refuses to release if the tag and the `.toc` version differ. Tags containing `alpha` or `beta`
(for example `0.6.0-beta1`) are uploaded to CurseForge as alpha/beta files.

If a run fails (a missing secret, say), fix the cause and click **Re-run jobs** on the run. To release an
existing tag without making a new release, use **Actions > Release > Run workflow**.

## Checking locally

```sh
scripts/package.sh                 # builds dist/CoinForge-<version>.zip
DRY_RUN=1 CF_API_KEY=... CF_PROJECT_ID=... scripts/upload-curseforge.sh dist/CoinForge-0.4.0.zip 0.4.0
```

`DRY_RUN=1` prints the CurseForge metadata instead of uploading.
