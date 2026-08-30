# Changelog — Vitals

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Newest entry first.

## Unreleased

### Added
- Disk alarm now `launchctl kickstart`s `dev.ancplua.disk-guard` the moment it
  latches, so cleanup starts immediately instead of at disk-guard's next poll.

### Fixed
- Claude usage no longer triggers the macOS Keychain dialog. The credential
  is read through `/usr/bin/security find-generic-password`, the same binary
  Claude Code writes it with, so it is always on the item's ACL. The previous
  in-process `SecItemCopyMatching` read depended on "Always Allow", which is
  bound to one exact ad-hoc-signed build and is dropped whenever Claude Code
  recreates the item. The binary-fingerprint authorization state in
  UserDefaults is gone with it. If the Keychain does refuse a read, background
  polling stops until the user hits Refresh instead of re-prompting.
- The Refresh row now shows the real age of the last Claude fetch
  ("Updated 12s ago") and updates live; clicking it refetches in place instead
  of closing the menu.

### Added
- Local Claude Code sessions (`~/.claude/sessions/<pid>.json`) are listed in
  the Claude section: name, working directory, busy/idle, age. Dead pids,
  stale entries, and cloud sessions are filtered. `CLAUDE_CONFIG_DIR` is
  honored via the new `ClaudeHome` path resolver.
- `vitals claude` prints the Claude section headlessly (status, usage rows,
  local sessions) for health checks and prompt-free verification.
- Disk headroom now follows macOS's capacity available for important usage,
  matching Finder for user-facing display, severity, and low-disk alarms.
- Disk values now use decimal GB labels instead of presenting binary GiB as
  GB, and the detail view distinguishes available capacity from free space
  immediately on disk.

### Added
- The packaged app declares its user-visible disk-space API use in a privacy
  manifest.

### Removed
- The duplicate `vitals disk` filesystem walker. GNU `du` remains the
  canonical manual disk-usage scanner while Vitals retains constant-time disk
  headroom telemetry.

### Changed
- Source ownership moved into `human-plugins`.
- The app is built in an isolated scratch directory and installed under
  `~/Applications` through the managed current-release link.

### Added
- Deterministic package, strict ad-hoc signature check, installed snapshot
  health, and atomic rollback exercise.

## [catalog-linked] - 2026-07-30

### Changed
- Canonical repository and collection entry now link to each other and are
  enforced by the repository-wide five-minute link-integrity gate.
- Replaced the obsolete no-standing-clone instruction with the actual
  canonical checkout at `~/RiderProjects/qyl-workspace/vitals`.

## [no-local-clone] - 2026-07-10

### Changed
- Standing local clone (`~/RiderProjects/qyl-workspace/vitals`) deleted after
  verifying clean tree and zero unpushed commits. Canonical home is now
  github.com/ANcpLua/vitals only; clone on demand. Installed runtime artifacts
  (`/Applications/Vitals.app`, LaunchAgent) untouched.

## [onboarded] - 2026-07-10

### Added
- Federated onboarding into human-plugins: docs triplet + drift-checked copy
  of the installed LaunchAgent (`launchd/dev.ancplua.vitals.plist`). Verified
  byte-identical to both the installed plist and the canonical repo's copy at
  onboarding time. App version 0.1.0 installed at `/Applications/Vitals.app`.

## [1.0.0] - 2026-06-13

### Added
- Original deployment (reconstructed from plist mtime 2026-06-13): LaunchAgent
  `dev.ancplua.vitals` starting `/Applications/Vitals.app` (`vitals bar`) at
  login, restart-on-crash (`KeepAlive.SuccessfulExit=false`), manual quit
  respected until next login.
