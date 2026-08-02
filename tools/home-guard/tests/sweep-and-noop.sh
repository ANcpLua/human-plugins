#!/usr/bin/env bash
set -euo pipefail

executable="$1"
test_home="$2"

rm -rf "$test_home"
mkdir -p "$test_home/KeepDir"
touch "$test_home/.keep-dotfile" "$test_home/AGENTS.md" "$test_home/stray.txt"
ln -s /nonexistent "$test_home/broken-link"

HOME="$test_home" "$executable"

# strays moved, allowed entries untouched
[ -f "$test_home/REVIEW-REQUIRED/stray.txt" ]
[ -L "$test_home/REVIEW-REQUIRED/broken-link" ]
[ ! -e "$test_home/stray.txt" ]
[ ! -L "$test_home/broken-link" ]
[ -f "$test_home/AGENTS.md" ]
[ -f "$test_home/.keep-dotfile" ]
[ -d "$test_home/KeepDir" ]
grep -q "moved: stray.txt" "$test_home/Library/Logs/home-guard.log"

# second run is a strict no-op
HOME="$test_home" "$executable"
[ "$(ls "$test_home/REVIEW-REQUIRED" | wc -l | tr -d ' ')" = "2" ]
[ -f "$test_home/AGENTS.md" ]
