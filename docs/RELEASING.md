# Releasing

A release is one tag push. GitHub Actions (`.github/workflows/release.yml`) then:

1. lints and runs the tests,
2. builds `dist/CoinForge-<version>.zip` with `scripts/package.sh` (only the files the game needs),
3. creates a GitHub release with the zip and the newest `CHANGELOG.md` entry as notes,
4. uploads the zip to CurseForge as a **WoW Forever (1.60.1)** file with `scripts/upload-curseforge.sh`.

## One-time setup

1. **Create the CurseForge project** at <https://authors.curseforge.com> (World of Warcraft > Addons), with
   category *Auction & Economy* and the description from [CURSEFORGE.md](CURSEFORGE.md). New projects are
   reviewed by CurseForge moderators before they go public.
2. **Note the project id**, the number shown on the project's overview page.
3. **Create an API token** at <https://authors.curseforge.com/account/api-tokens>.
4. In the GitHub repo, open **Settings > Secrets and variables > Actions** and add:
   - secret **`CF_API_KEY`**: the API token
   - variable **`CF_PROJECT_ID`**: the project id

## Each release

1. Update `## Version:` in `CoinForge.toc`, `ns.version` in `src/Core/Namespace.lua`, and add a
   `## x.y.z (date)` entry at the top of `CHANGELOG.md`.
2. Commit and push, then tag the same version:

   ```sh
   git tag v0.4.0
   git push origin main v0.4.0
   ```

Tags containing `alpha` or `beta` (for example `v0.5.0-beta1`) are published as alpha/beta files and GitHub
pre-releases. The workflow refuses to release if the tag and the `.toc` version differ.

## Checking locally

```sh
scripts/package.sh                 # builds dist/CoinForge-<version>.zip
DRY_RUN=1 CF_API_KEY=... CF_PROJECT_ID=... scripts/upload-curseforge.sh dist/CoinForge-0.4.0.zip 0.4.0
```

`DRY_RUN=1` prints the CurseForge metadata instead of uploading.
