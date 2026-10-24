#!/bin/bash
# Prints Tape's download counts: each deleted release from downloads.tsv (publish-release.sh
# records it before deleting the release, since GitHub drops the count with it), the current
# release live from GitHub, then the total. The installer, Homebrew and the in-app updater all
# download Tape.dmg, so these are downloads, not people.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=zlichtman/Tape
# downloads.tsv lives in the main checkout, even when this runs from a linked worktree.
tally="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/downloads.tsv"
{
  [[ -f "$tally" ]] && tail -n +2 "$tally" | cut -f1,2
  gh release view --repo "$repo" --json tagName,assets --jq '"\(.tagName) (current)\t\([.assets[].downloadCount] | add // 0)"'
} | awk -F'\t' '{ print; total += $2 } END { print "all releases\t" total + 0 }' | column -t -s $'\t'
