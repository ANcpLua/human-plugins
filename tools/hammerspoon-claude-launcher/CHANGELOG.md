# Changelog

## Unreleased

- Migrated from `ANcpLua/hammerspoon-setup`.
- Removed the duplicated prompt, obsolete model pin, permission bypass, shell
  detachment, and package-install bootstrap.
- Replaced shell execution with `hs.task` and made terminal and command policy
  explicit environment inputs.
- Added deterministic packaging, installed health, and rollback.
