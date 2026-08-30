# Changelog — disk-guard

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Newest entry first.

## Unreleased

### Changed
- Trigger is now a 5-minute `StartInterval` with `RunAtLoad`, plus an
  immediate `launchctl kickstart` from vitals when its disk alarm latches,
  instead of a single daily calendar run.
- Threshold is vitals' red line: bytes available on `/System/Volumes/Data`,
  decimal GB, default 10 GB (was `df -g /`, 25 GiB). Full passes are limited
  to one per hour.
- Cleanup is split into tier 1 (always safe, never anything Rider holds open)
  and tier 2 (idle `bin`/`obj`/`artifacts`, `~/.cache/typescript`, NuGet
  global-packages), which runs only when Rider is not running and tier 1 left
  the disk below threshold. The old "second fire within seven days" escalation
  is gone.
- No-op runs write only a heartbeat; the log holds fires only, and every fire
  ends with a notification stating the reclaimed amount.
- repo-hygiene check runs once per day instead of once per invocation.
- Source ownership moved into `human-plugins`.
- Launchd paths are rendered by the atomic installer instead of containing a
  fixed username.
- Launchd classifies cleanup as background, low-priority filesystem I/O.

### Added
- `disk-guardd status`: available space vs threshold, Rider gate, last
  heartbeat, last fire, launchd run count.
- Tier 1 gains `~/.npm/_cacache` and `docker system prune -f` (only while
  OrbStack is already running, so the CLI cannot boot the VM).
- Threshold no-op test, deterministic package, installed health check, and
  rollback exercise.

## [catalog-linked] - 2026-07-30

### Changed
- Canonical repository and collection entry now link to each other and are
  enforced by the repository-wide five-minute link-integrity gate.
- Repository is public after a zero-finding full-history secret scan; the
  canonical local checkout is `~/disk-guard`.

## [redeployed] - 2026-07-28

### Changed
- Installed `~/.local/bin/disk-guardd` updated to canonical repo commit
  `9bc8708`: allowlist gains `$TMPDIR/.com.google.Chrome.*` (120min) and
  `/opt/homebrew/var/homebrew/tmp` (1d), tool-native pruning gains
  `brew cleanup --prune=all`. LaunchAgent **unchanged** — no drift, the
  `launchd/` copy here stays byte-identical to the installed plist.
- Motivation is a host observation, which is why it is recorded here: Chrome
  leaks a ~490 MB framework copy into `$TMPDIR` per launch (~17/day). A manual
  sweep on 2026-07-28 found 51 of them (9.9 GB) and took free space 19 → 36 GiB.
  The previous allowlist never scanned `$TMPDIR`, so the agent had been firing
  correctly and reclaiming only ~3 GB against a leak an order of magnitude larger.

## [onboarded] - 2026-07-25

### Added
- Federated onboarding into human-plugins: docs triplet + drift-checked copy
  of the installed LaunchAgent (`launchd/dev.ancplua.disk-guard.plist`),
  verified byte-identical to the installed plist and the canonical repo's
  copy. Agent was built, installed, and live-tested (both no-op and fire
  paths) earlier the same day; canonical repo at commit `7fa58d6`
  (allowlist-based pruning).
