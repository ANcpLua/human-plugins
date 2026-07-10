# human-plugins

AI-maintained monorepo of background tools ("human plugins") for the owner's
macOS host and peripherals. Not written for human consumption — agents read
[CLAUDE.md](CLAUDE.md) first (mandatory drift check), then the per-tool docs.

## Tools

| Tool | What it does | Entry points |
|---|---|---|
| [airpods-mic-guard](tools/airpods-mic-guard/README.md) | Event-driven CoreAudio daemon that keeps AirPods in hi-fi A2DP while listening, yields the mic during real calls | [CLAUDE.md](tools/airpods-mic-guard/CLAUDE.md) · [CHANGELOG.md](tools/airpods-mic-guard/CHANGELOG.md) |
| [heizoel-monitor](tools/heizoel-monitor/README.md) | Heating-oil price monitor (retired; script lost with its parent repo) | [CLAUDE.md](tools/heizoel-monitor/CLAUDE.md) · [CHANGELOG.md](tools/heizoel-monitor/CHANGELOG.md) |

Repo-level history: [CHANGELOG.md](CHANGELOG.md).

Candidates not yet onboarded: `vitals` (menu-bar hardware monitor,
`dev.ancplua.vitals`), `memcheck`, `cc8` (both in `~/.local/bin`).
