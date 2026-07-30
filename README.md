# human-plugins

AI-maintained monorepo of background tools ("human plugins") for the owner's
macOS host and peripherals. Not written for human consumption — agents read
[CLAUDE.md](CLAUDE.md) first (mandatory drift check), then the per-tool docs.
The machine-readable ownership and federation map is
[catalog.json](catalog.json); CI validates every local/external link and every
federated backlink on push, pull request, and every five minutes.

## Tools

| Tool | What it does | Entry points |
|---|---|---|
| [airpods-mic-guard](tools/airpods-mic-guard/README.md) | Event-driven CoreAudio daemon that keeps AirPods in hi-fi A2DP while listening, yields the mic during real calls | [Source](tools/airpods-mic-guard/src/airpods-mic-guardd.swift) · [CLAUDE.md](tools/airpods-mic-guard/CLAUDE.md) · [CHANGELOG.md](tools/airpods-mic-guard/CHANGELOG.md) |
| [heizoel-monitor](tools/heizoel-monitor/README.md) | Heating-oil price monitor (retired; script lost with its parent repo) | [CLAUDE.md](tools/heizoel-monitor/CLAUDE.md) · [CHANGELOG.md](tools/heizoel-monitor/CHANGELOG.md) |
| [vitals](tools/vitals/README.md) | Menu-bar CPU/memory/disk monitor (federated: code in [ANcpLua/vitals](https://github.com/ANcpLua/vitals); deployment tracked here) | [CLAUDE.md](tools/vitals/CLAUDE.md) · [CHANGELOG.md](tools/vitals/CHANGELOG.md) |
| [disk-guard](tools/disk-guard/README.md) | Threshold-triggered disk cleanup: daily launchd check, prunes an allowlist of regenerable data only when free space < 25 GiB (federated: code in [ANcpLua/disk-guard](https://github.com/ANcpLua/disk-guard); deployment tracked here) | [CLAUDE.md](tools/disk-guard/CLAUDE.md) · [CHANGELOG.md](tools/disk-guard/CHANGELOG.md) |

Repo-level history: [CHANGELOG.md](CHANGELOG.md).

Candidates not yet onboarded: `memcheck`, `cc8` (both in `~/.local/bin`).
