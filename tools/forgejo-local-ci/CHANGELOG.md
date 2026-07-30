# Changelog

## Unreleased

- Migrated from `ANcpLua/forgejo-local-ci`.
- Replaced eight coupled shell scripts with one standard-library Python CLI.
- Separated immutable releases from persistent runtime state and removed the
  destructive reset command.
- Added deterministic macOS/Linux packages, installed health, and rollback.
