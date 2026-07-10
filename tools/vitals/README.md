# vitals (federated — source lives in its own repo)

Native macOS monitor: live CPU by process, real memory breakdown with the
kernel's authoritative pressure level, disk headroom, and what-if kill
estimates. One Swift binary, menu-bar app mode. No daemon dependencies, no
persistence, no network.

## Canonical home

Source, build, and installer: **github.com/ANcpLua/vitals** (no standing local
clone — clone on demand, work, push, delete). This monorepo entry does NOT vendor the source —
vitals predates human-plugins and has its own healthy repo/history. Here we
track only what makes it a "human plugin": the login-item deployment.

## Deployment (what this entry tracks)

- Installed app: `/Applications/Vitals.app` (bundle `dev.ancplua.vitals`,
  runs `vitals bar` — NSStatusItem menu-bar app).
- LaunchAgent `~/Library/LaunchAgents/dev.ancplua.vitals.plist` (label
  `dev.ancplua.vitals`): `RunAtLoad`, `KeepAlive.SuccessfulExit=false` —
  starts at login, restarts on crash, and a manual ⌘Q stays quit until next
  login. Repo copy in `launchd/` is drift-checked against the installed one.
- Event posture: resident menu-bar app that polls system stats while visible —
  that is its job (a monitor must sample). Idle cost ~18 MB RSS, ~0.2% CPU.
- Alerts: native notification when disk free < 10 GB or memory pressure
  escalates.

## Why it is not vendored

Doctrine distinction vs [heizoel-monitor](../heizoel-monitor/README.md):
heizoel died because launchd pointed into another repo's *working tree*.
vitals' launchd points at an *installed artifact* (`/Applications/Vitals.app`)
that survives independently of any repo checkout — that coupling is safe.

See [CLAUDE.md](CLAUDE.md) and [CHANGELOG.md](CHANGELOG.md).
