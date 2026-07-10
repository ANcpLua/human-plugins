#!/bin/zsh
# Keep AirPods in hi-fi A2DP for LISTENING, but get out of the way for CALLS.
#
# The problem: AirPods can't do hi-fi output and act as a mic at the same time
# (Bluetooth limit). If macOS makes AirPods the default INPUT while nothing is
# actually using the mic, the whole link drops to HFP "phone call" quality for
# no reason. But when you ARE on a call, you WANT the AirPods mic.
#
# How we tell you're on a call: NOT by listening to sound (ventilator, silence,
# chair squeaks are all irrelevant). We check a hardware ownership flag — "does
# any app currently have the mic stream OPEN?" Discord/Teams/Zoom/etc. open the
# stream on join and hold it the whole time (even while you're muted), so the
# flag stays 1 for the entire call. mic-active (from mic-active.swift) prints
# that flag: 1 = some app owns the mic, 0 = nobody does.
#
# Grace window: we only push the mic OFF AirPods after the mic has read idle for
# GRACE consecutive checks. That way a brief blip — e.g. AirPods reconnecting
# mid-call, when the stream drops for a poll or two — never yanks your mic away.
SAS=/opt/homebrew/bin/SwitchAudioSource
MIC_ACTIVE="${0:A:h}/mic-active"
COUNT_FILE="${TMPDIR:-/tmp/}airpods-mic-guard.idlecount"
GRACE=3                       # consecutive idle checks required before switching
[ -x "$SAS" ] || exit 0

# Manual off-switch: `touch ~/.airpods-guard-off` to fully disable the guard.
[ -e "$HOME/.airpods-guard-off" ] && exit 0

reset_count() { print 0 >| "$COUNT_FILE" 2>/dev/null; }

out=$("$SAS" -c -t output)
in=$("$SAS" -c -t input)
lout=${out:l}
lin=${in:l}

# Only relevant when AirPods are BOTH output and input (the bad HFP mode).
if [[ "$lout" != *airpod* || "$lin" != *airpod* ]]; then
  reset_count
  exit 0
fi

# AirPods are the mic. If an app owns the mic, you're on a call — leave it be.
if [ -x "$MIC_ACTIVE" ] && [ "$("$MIC_ACTIVE")" = "1" ]; then
  reset_count
  exit 0
fi

# Mic idle. Bump the consecutive-idle counter; only act past the grace window.
count=0
[ -f "$COUNT_FILE" ] && count=$(< "$COUNT_FILE")
[[ "$count" == <-> ]] || count=0     # guard against missing/garbage state
count=$((count + 1))

if (( count < GRACE )); then
  print "$count" >| "$COUNT_FILE" 2>/dev/null
  exit 0
fi

# Idle long enough → you're just listening. Push input off AirPods so they snap
# back to hi-fi A2DP. Prefer the built-in mic; else first non-AirPods input.
builtin=$("$SAS" -a -t input | grep -i 'macbook' | head -1)
[ -z "$builtin" ] && builtin=$("$SAS" -a -t input | grep -vi 'airpod' | head -1)
[ -n "$builtin" ] && "$SAS" -t input -s "$builtin" >/dev/null 2>&1
reset_count
