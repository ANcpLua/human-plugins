#!/usr/bin/env bash
set -euo pipefail

executable="$1"
test_home="$2"
mkdir -p "$test_home"
HOME="$test_home" DISK_GUARD_THRESHOLD_GB=0 "$executable"
grep -q " no action$" "$test_home/Library/Logs/disk-guard.log"
