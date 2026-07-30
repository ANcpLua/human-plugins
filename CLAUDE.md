# human-plugins — agent operating protocol

This repo is maintained exclusively by AI agents. No human reads or edits it.
It is the owner's "plugin system" for his OS and peripherals: each directory
under `tools/` is one plugin, self-contained, with its own README.md (what/why),
CLAUDE.md (agent guidance), and CHANGELOG.md (history, newest entry first).

## MANDATORY FIRST ACTION — drift check

Before ANY other work in this repo, run:

```sh
scripts/drift-check.sh
```

- Exit 0 → proceed with the task.
- Exit 1 → **STOP. Do not continue the task.** Produce a Drift Report
  (template below), deliver it to the user, and wait for their decision.
  Continuing work on top of undocumented changes is strictly prohibited.

Drift means: uncommitted changes, a commit that touched a tool without
updating that tool's CHANGELOG.md, or installed artifacts (binaries, launchd
plists) that differ from the repo copies, or a broken catalog/federation link.

## Drift Report template

```
## Drift report — <date>

### What was found
<exact drift: files, diffs, commits, installed-vs-repo mismatches>

### Memory cross-check
<If the cause of the drift is documented in Claude auto-memory
(~/.claude/projects/*/memory/) instead of a changelog: propose deleting it
from memory and appending it as the NEWEST entry of the affected tool's
CHANGELOG.md, so continuation of the task is unblocked. Name the task and
its goal if still identifiable; otherwise list what remains uncertain and
ask.>

### Proposed adjustments
<anything in the found trail, code, or data you want to change or flag>

### Other
<anything relevant that the template does not cover>
```

## Changelog rules

- Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
  newest entry at the TOP of the file.
- Because newest-first is guaranteed, agents read only the top entries they
  need — never the whole file. Changelogs may grow unboundedly; that is fine.
- Every commit that touches a tool MUST update that tool's CHANGELOG.md in
  the same commit (drift-check enforces this).
- Repo-level structural changes go in the root `CHANGELOG.md`.

## Repository and link integrity

- `catalog.json` is the exhaustive ownership map. Every directory under
  `tools/` appears exactly once as embedded, federated, or retired.
- Federated tool READMEs link to their canonical repository, and each
  canonical README links back to the exact collection entry.
- Run `python3 scripts/validate-links.py` before every commit. GitHub Actions
  runs the same validator on pushes, pull requests, and hourly; scheduled
  failures open an issue and a later successful run closes it.
- A repository rename, visibility change, transfer, deletion, default-branch
  change, or collection move is incomplete until `catalog.json`, both
  directions of documentation, and the validator all pass.

## Design doctrine (applies to every tool)

- Event-driven over polling. Processes sleep until an event arrives.
- Config-driven, explainable: every line must be the simplest solution to a
  forever-lasting problem until proven wrong
  ([the three virtues](https://thethreevirtues.com/): laziness, impatience,
  hubris — all three).
- A tool is: source in `src/`, deployment in `launchd/` (or equivalent),
  `Makefile` with `build` / `install` / `uninstall` / `status`, docs triplet
  README.md + CLAUDE.md + CHANGELOG.md. Retired artifacts go in `legacy/`.

## Index

| Tool | Source | Docs | Status |
|---|---|---|---|
| airpods-mic-guard | [embedded source](tools/airpods-mic-guard/src/airpods-mic-guardd.swift) | [README](tools/airpods-mic-guard/README.md) · [CLAUDE](tools/airpods-mic-guard/CLAUDE.md) · [CHANGELOG](tools/airpods-mic-guard/CHANGELOG.md) | active (launchd daemon) |
| heizoel-monitor | retired; source unavailable | [README](tools/heizoel-monitor/README.md) · [CLAUDE](tools/heizoel-monitor/CLAUDE.md) · [CHANGELOG](tools/heizoel-monitor/CHANGELOG.md) | retired 2026-07-10 |
| vitals | [ANcpLua/vitals](https://github.com/ANcpLua/vitals) | [README](tools/vitals/README.md) · [CLAUDE](tools/vitals/CLAUDE.md) · [CHANGELOG](tools/vitals/CHANGELOG.md) | active (federated) |
| disk-guard | [ANcpLua/disk-guard](https://github.com/ANcpLua/disk-guard) | [README](tools/disk-guard/README.md) · [CLAUDE](tools/disk-guard/CLAUDE.md) · [CHANGELOG](tools/disk-guard/CHANGELOG.md) | active (federated) |
