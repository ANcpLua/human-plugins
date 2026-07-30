# Vitals

Native Swift menu-bar telemetry for CPU, memory pressure, disk headroom,
processes, and Claude usage. It also exposes non-interactive commands used by
tests and installed health checks.

```bash
swift run -c release selftest
swift run -c release claude-selftest
swift run -c release vitals snapshot
```

`tool.json` builds and signs an ad-hoc `Vitals.app`, verifies it, exercises the
packaged binary, and tests atomic install and rollback.
