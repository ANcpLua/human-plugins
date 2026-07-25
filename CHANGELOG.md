# Changelog — human-plugins (repo level)

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Newest entry first.

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
