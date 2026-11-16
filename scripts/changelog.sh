#!/usr/bin/env bash
# Prints the newest CHANGELOG.md entry (from the first "## " heading up to the
# next one), used as the release notes on GitHub and CurseForge.
set -euo pipefail
cd "$(dirname "$0")/.."
awk '/^## /{n++} n==1' CHANGELOG.md
