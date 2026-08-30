#!/usr/bin/env bash
set -euo pipefail

executable="$1"
test_home="$2"
mkdir -p "$test_home"
# Threshold 0 GB can never trip: the run must only leave a heartbeat behind.
HOME="$test_home" DISK_GUARD_THRESHOLD_GB=0 "$executable"
test -f "$test_home/.local/state/disk-guard/last-check"
! grep -qs FIRE "$test_home/Library/Logs/disk-guard.log"
# status must always exit 0 and name the threshold, loaded agent or not.
HOME="$test_home" DISK_GUARD_THRESHOLD_GB=0 "$executable" status | grep "threshold 0 GB" >/dev/null
