# Changelog — human-plugins (repo level)

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Newest entry first.

## Unreleased

### Added
- Manifest-driven check, build, test, package, smoke, isolated deploy, health,
  and rollback orchestration.
- Deterministic release packages, SHA-256 records, GitHub artifact attestations,
  failure diagnostics, and an atomic updater.
- Canonical macOS/Linux implementations of cc8, memcheck, opusbreak, and
  repo-hygiene.

### Changed
- This repository is now the source of truth for Vitals and Disk Guard.
- Heizöl Monitor is a dependency-free macOS/Linux daemon instead of a thin
  wrapper around the generic whcli/Tauri product.

### Removed
- Federated ownership, the retired Heizöl shell, and the AirPods polling-era
  implementation.

## [1.3.0] - 2026-07-30

### Added
- Exhaustive `catalog.json` ownership map for embedded, federated, and retired
  tools.
- Local/external URL and reciprocal-federation validator, enforced by GitHub
  Actions on every push and pull request plus hourly. Scheduled failures open
  an issue; successful recovery closes it.

### Changed
- `human-plugins`, `vitals`, and `disk-guard` are public after full-history
  secret scans returned zero findings, so all catalog links work without a
  cross-repository credential.

## [1.2.0] - 2026-07-25

### Added
- Tool `disk-guard` onboarded as the second federated tool: code in its
  canonical private repo (github.com/ANcpLua/disk-guard); this repo tracks
  the deployment (drift-checked launchd plist, script-presence check, docs
  triplet). drift-check.sh extended accordingly.

## [1.1.0] - 2026-07-10

### Added
- Tool `vitals` onboarded as the first *federated* tool: code stays in its
  canonical repo (github.com/ANcpLua/vitals); human-plugins tracks the
  deployment (drift-checked launchd plist + docs triplet). Establishes the
  federated-tool pattern for tools with their own healthy repos.

## [1.0.0] - 2026-07-10

### Added
- Repo created: root README.md (index), CLAUDE.md (agent protocol: mandatory
  drift check, drift report template, changelog rules, design doctrine),
  `scripts/drift-check.sh`.
- Tool `airpods-mic-guard` v2.0.0 (event-driven daemon; see its changelog).
- Tool `heizoel-monitor` (docs + preserved plist only; retired on arrival).
