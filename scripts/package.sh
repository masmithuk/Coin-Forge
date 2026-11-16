#!/usr/bin/env bash
# Builds the installable addon zip: dist/ForeverGold-<version>.zip
#
# The zip holds a single ForeverGold/ folder with only what the game needs
# (the .toc, Main.lua, src/) plus the licence, readme and changelog. Tests,
# docs and tooling are left out.
#
# Usage: scripts/package.sh            -> uses the version in ForeverGold.toc
#        scripts/package.sh 1.2.3      -> also checks the .toc says 1.2.3
set -euo pipefail

cd "$(dirname "$0")/.."

toc_version=$(sed -n 's/^## Version: *//p' ForeverGold.toc | tr -d '\r')
version="${1:-$toc_version}"
version="${version#v}"
if [ "$version" != "$toc_version" ]; then
  echo "Version mismatch: asked for $version but ForeverGold.toc says $toc_version." >&2
  echo "Update '## Version:' in ForeverGold.toc (and CHANGELOG.md) before releasing." >&2
  exit 1
fi

# Every file the .toc loads must exist, or the addon breaks in game.
missing=0
while read -r file; do
  if [ ! -f "$file" ]; then echo "Listed in ForeverGold.toc but missing: $file" >&2; missing=1; fi
done < <(grep -E '^[^#].*\.lua\s*$' ForeverGold.toc | tr -d '\r')
[ "$missing" -eq 0 ] || exit 1

out="dist/ForeverGold-$version.zip"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/ForeverGold" dist
cp -R ForeverGold.toc Main.lua src LICENSE README.md CHANGELOG.md "$stage/ForeverGold/"
rm -f "$out"
(cd "$stage" && zip -qr -X "$OLDPWD/$out" ForeverGold)
echo "$out"
