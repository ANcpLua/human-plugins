# Changelog

## Unreleased

- Migrated the native launcher from `ANcpLua/onlyfitch`.
- Deleted the unrelated Tauri scaffold, macOS 26-only UI, placeholder secrets,
  embedded personal channel list, suppressive catches, and plaintext token
  storage.
- Rebuilt the app for macOS 14 with Keychain credentials, strict configuration,
  standard Swift Package builds, deterministic packaging, health, and rollback.
