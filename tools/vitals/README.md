# Vitals

Native Swift menu-bar telemetry for CPU, memory pressure, disk headroom,
processes with a 60 s per-process CPU sparkline, optional per-process
network rates via `nettop`, and Claude usage plus copyable local sessions. Disk headroom follows macOS's capacity available
for important usage—the value Finder reports—and also exposes the immediately
free capacity for diagnosis. It also exposes non-interactive commands used by
tests and installed health checks.

```bash
swift run -c release selftest
swift run -c release claude-selftest
swift run -c release vitals snapshot
swift run -c release vitals claude
```

Claude usage is read from the `Claude Code-credentials` Keychain item through
`/usr/bin/security`, which Claude Code itself uses to write it, so no Keychain
dialog is shown. Local Claude Code sessions come from
`~/.claude/sessions/<pid>.json` (or `$CLAUDE_CONFIG_DIR/sessions`).

`tool.json` builds and signs an ad-hoc `Vitals.app`, verifies it, exercises the
packaged binary, and tests atomic install and rollback.
