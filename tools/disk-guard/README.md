# disk-guard

Reclaims regenerable data the moment the SSD goes red. Red is the same line
vitals draws: fewer than **10 GB available** on `/System/Volumes/Data`
(`DISK_GUARD_THRESHOLD_GB`). Above it every run is a silent no-op.

Two triggers, one script:

- launchd `StartInterval` every 5 minutes, `RunAtLoad` so it is armed right
  after login/restart;
- vitals `launchctl kickstart`s the agent the instant its disk alarm latches.

A full pass runs at most once per hour (`DISK_GUARD_COOLDOWN_MIN`).

## What it deletes

**Tier 1 — always.** Nothing Rider maps or holds open: old codex sessions and
logs, leaked Chrome framework copies in `$TMPDIR`, idle `~/.cache/*` subdirs,
`~/.npm/_cacache`, Homebrew scratch + `brew cleanup`, `pnpm store prune`, the
NuGet HTTP cache, `docker system prune` (only while OrbStack is already
running).

**Tier 2 — only when Rider is closed** and tier 1 did not get back above the
threshold: idle git-ignored `bin`/`obj`/`artifacts` under `~/RiderProjects`,
`~/.cache/typescript`, and the NuGet global-packages folder.

`~/Library/Caches/JetBrains` is never touched. The allowlist with age
semantics is the header comment of `src/disk-guardd`; read it before changing
anything.

## Is it alive?

```sh
disk-guardd status
```

prints available space vs threshold, whether Rider is gating tier 2, the last
heartbeat, the last fire, and the launchd run count since boot. The log at
`~/Library/Logs/disk-guard.log` only contains fires; each one ends with a
macOS notification stating how much was reclaimed.

Delivery, installed health, and launchd ownership are defined by `tool.json`.
