# Changelog — disk-guard (deployment record)

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Newest entry first.
Code history lives in the canonical repo (github.com/ANcpLua/disk-guard); this
file tracks the deployment on this host only.

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
