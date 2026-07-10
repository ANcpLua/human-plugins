# airpods-mic-guard — agent guidance

Read root `../../CLAUDE.md` first (mandatory drift check applies before any
work here). History lives in [CHANGELOG.md](CHANGELOG.md) — newest entry first;
read only the top entries you need. Every change to this tool MUST append a new
topmost CHANGELOG.md entry in the same commit.

## Invariants (do not regress)

- **No polling.** The daemon sleeps in `CFRunLoopRun()`; the only timer ever
  armed is the one-shot 15 s grace `DispatchWorkItem`, and only while AirPods
  are in the bad in+out state with an idle mic. Anything reintroducing
  `StartInterval`, periodic timers, or busy loops is a regression.
- **Never fight a call.** Mic-in-use detection is
  `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input —
  stream ownership, not audio content. The grace re-verifies before switching.
- **Kill switch**: `touch ~/.airpods-guard-off` disables all switching
  (checked on every evaluation). Preserve it.
- All state mutations run on the single serial queue
  `dev.ancplua.airpods-mic-guard` — keep it that way; no locks needed.
- Single source file, CoreAudio + Foundation only, no dependencies.

## Layout

| Path | Role |
|---|---|
| `src/airpods-mic-guardd.swift` | the daemon (single file) |
| `launchd/com.ancplua.airpods-mic-guard.plist` | KeepAlive launchd job (repo copy = installed copy; drift-check diffs them) |
| `Makefile` | `build` / `install` / `uninstall` / `status` |
| `legacy/` | retired v1: 5 s-poll shell script, `mic-active.swift`, old StartInterval plist |

## Operations

- Installed binary: `~/.local/bin/airpods-mic-guardd`; log:
  `~/Library/Logs/airpods-mic-guard.log`.
- After editing the plist or source: `make install` (it boots the job out and
  back in), then commit repo copy AND changelog entry together — otherwise the
  next agent's drift check fails.
- Debugging: `make status`; run the binary in foreground to watch decisions
  live (it logs every grace arm/cancel/switch with reasons).
