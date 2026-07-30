# Changelog

## Unreleased

- Migrated the generic engine from the private `ANcpLua/qyl-discord-sync`
  repository without private channel or guild identifiers.
- Removed PyYAML, the unused guild field, hard-coded user paths, and monolithic
  import-time configuration.
- Added strict configuration boundaries, deterministic YAML-compatible output,
  attachment budgeting, macOS/Linux schedules, installed health, and rollback.
