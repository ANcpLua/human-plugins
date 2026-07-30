# Changelog

## Unreleased

- Migrated from `ANcpLua/forgejo-local-ci`.
- Replaced eight coupled shell scripts with one standard-library Python CLI.
- Separated immutable releases from persistent runtime state and removed the
  destructive reset command.
- Treats transient HTTP startup disconnects as readiness state, waits for
  authenticated Git readiness, and writes the runner secret as exactly 40
  bytes.
- Added deterministic macOS/Linux packages, installed health, and rollback.
