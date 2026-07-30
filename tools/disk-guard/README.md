# disk-guard

Daily macOS cleanup that no-ops while free disk space is above 25 GiB. Below the
threshold it prunes only explicitly listed, regenerable caches and old logs.
NuGet packages are cleared only on a second critically-low-space run within
seven days.

```bash
DISK_GUARD_THRESHOLD_GB=0 disk-guardd
tail ~/Library/Logs/disk-guard.log
```

Review `src/disk-guardd` before changing the deletion allowlist. Delivery,
installed health, and launchd ownership are defined by `tool.json`.
