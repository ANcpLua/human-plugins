# memcheck

Cross-platform memory, swap, and process snapshot with text and JSON output.

```bash
memcheck
memcheck --match 'claude|codex|rider'
memcheck --json
```

On macOS it derives pressure-relevant used memory from active, wired, and
compressed VM pages. On Linux it uses `MemAvailable` from `/proc/meminfo`.
