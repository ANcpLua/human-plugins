# Changelog — Vitals

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Newest entry first.

## Unreleased

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
