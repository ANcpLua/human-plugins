# disk-guard (federated — source lives in its own repo)

Threshold-triggered disk cleanup agent. Runs daily at 12:00 via launchd and
no-ops unless free space is below 25 GiB. When it fires, it prunes only an
explicit allowlist of regenerable data (stale build output, old Codex
sessions/logs, idle caches) plus tool-native pruning (`pnpm store prune`,
NuGet http-cache). A second fire within 7 days below 15 GiB escalates to a
full NuGet global-packages clear — everything in it restores from nuget.org.

Born 2026-07-25 after a manual sweep reclaimed ~35 GB (8.7 → 43 GiB free);
this agent prevents the regrowth from ever requiring that exercise again.

## Canonical home

Source, allowlist policy, and installer: **github.com/ANcpLua/disk-guard**
(private; no standing local clone — clone on demand, work, push, delete).
This monorepo entry tracks only the deployment.

## Deployment (what this entry tracks)

- Script: `~/.local/bin/disk-guardd` (zsh, installed executable).
- LaunchAgent `~/Library/LaunchAgents/dev.ancplua.disk-guard.plist` (label
  `dev.ancplua.disk-guard`): `StartCalendarInterval` daily 12:00,
  `RunAtLoad=false`. Repo copy in `launchd/` is drift-checked against the
  installed one.
- Log: `~/Library/Logs/disk-guard.log` · State: `~/.local/state/disk-guard.last-fire`.
- Event posture: launchd has no free-space event source, so the cheapest
  honest primitive is a daily scheduled check that exits immediately when
  disk is healthy (~ms of work, silent in the log). The *threshold* is the
  event; the timer is only how launchd lets us observe it.

## Manual test

```sh
DISK_GUARD_THRESHOLD_GB=99 ~/.local/bin/disk-guardd && tail ~/Library/Logs/disk-guard.log
```

Forces the fire path regardless of free space; remember it prunes for real.
