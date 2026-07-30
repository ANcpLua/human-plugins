# human-plugins

[![CI](https://github.com/ANcpLua/human-plugins/actions/workflows/ci.yml/badge.svg)](https://github.com/ANcpLua/human-plugins/actions/workflows/ci.yml)
[![Signed release](https://github.com/ANcpLua/human-plugins/actions/workflows/release.yml/badge.svg)](https://github.com/ANcpLua/human-plugins/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

AI-first source of truth for Alex's small macOS and Linux host tools. Each tool
declares one complete path from source to a deterministic release in
[`tool.json`](pipeline/tool.schema.json):

```text
check → build → test → package → smoke → isolated deploy → health → rollback
                                                            │
                       GitHub attestation + SHA-256 ────────┘
```

## Tools

| Tool | Platforms | Purpose |
|---|---|---|
| [airpods-mic-guard](tools/airpods-mic-guard/README.md) | macOS | Keeps AirPods on hi-fi output until an app owns the microphone |
| [cc8](tools/cc8/README.md) | macOS, Linux | Creates eight tmux workspaces for parallel coding agents |
| [disk-guard](tools/disk-guard/README.md) | macOS | Reclaims only allowlisted derived data below a disk threshold |
| [forgejo-local-ci](tools/forgejo-local-ci/README.md) | macOS, Linux | Runs an isolated local Forgejo and containerized Actions runner |
| [hammerspoon-claude-launcher](tools/hammerspoon-claude-launcher/README.md) | macOS | Opens and tiles agent terminals from a mouse or keyboard trigger |
| [memcheck](tools/memcheck/README.md) | macOS, Linux | Reports memory, swap, and matching process RSS |
| [opusbreak](tools/opusbreak/README.md) | macOS, Linux | Caches Anthropic status and renders concise advisories |
| [qyl-discord-sync](tools/qyl-discord-sync/README.md) | macOS, Linux | Mirrors versioned upstream documentation into Discord |
| [repo-hygiene](tools/repo-hygiene/README.md) | macOS, Linux | Finds committed build output without scanning file contents |
| [twitch-launcher](tools/twitch-launcher/README.md) | macOS | Shows Twitch channels and opens streams through Streamlink |
| [vitals](tools/vitals/README.md) | macOS | Native menu-bar CPU, memory, disk, process, and Claude telemetry |

[`catalog.json`](catalog.json) is the generated machine index. `AGENTS.md` is
the repository contract.

## Verify

```bash
./toolctl validate
./toolctl list
./toolctl verify --tool airpods-mic-guard --platform macos
```

Every command is executed as an argv array without shell interpolation. Logs,
packages, and checksums land in `.artifacts/`; CI preserves them when a job
fails.

## Install and update

Build and install a local package:

```bash
./toolctl verify --tool airpods-mic-guard --platform macos
./toolctl install \
  --tool airpods-mic-guard \
  --package .artifacts/packages/airpods-mic-guard-macos.tar.gz \
  --release local
```

Install the latest public release:

```bash
./toolctl update --tool airpods-mic-guard
```

Remote updates are downloaded with `gh`, checked against the release SHA-256,
verified with `gh attestation verify`, staged beside existing releases, and
switched atomically. A failed installed health check restores the prior release.

```bash
./toolctl status --tool airpods-mic-guard
./toolctl rollback --tool airpods-mic-guard
```

The project is free to use, fork, and modify under the [MIT License](LICENSE).
