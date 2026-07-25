# Changelog — disk-guard (deployment record)

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Newest entry first.
Code history lives in the canonical repo (github.com/ANcpLua/disk-guard); this
file tracks the deployment on this host only.

## [onboarded] - 2026-07-25

### Added
- Federated onboarding into human-plugins: docs triplet + drift-checked copy
  of the installed LaunchAgent (`launchd/dev.ancplua.disk-guard.plist`),
  verified byte-identical to the installed plist and the canonical repo's
  copy. Agent was built, installed, and live-tested (both no-op and fire
  paths) earlier the same day; canonical repo at commit `7fa58d6`
  (allowlist-based pruning).
