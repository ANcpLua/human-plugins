# disk-guard — agent guidance

Read root `../../CLAUDE.md` first (mandatory drift check). History in
[CHANGELOG.md](CHANGELOG.md), newest entry first.

**Federated tool**: source of truth for code is **github.com/ANcpLua/disk-guard**
(private). There is no standing local clone — clone on demand, work, push,
delete the clone. Code changes happen THERE. This entry owns only the
deployment record.

Rules:
- The repo copy `launchd/dev.ancplua.disk-guard.plist` must stay
  byte-identical to `~/Library/LaunchAgents/dev.ancplua.disk-guard.plist`
  AND to the canonical repo's copy (drift-check compares the installed one).
  Change all three in the same operation, with a new topmost changelog entry
  here.
- `~/.local/bin/disk-guardd` must exist and be executable (drift-check
  verifies presence, not content — script content is the canonical repo's
  concern; keep it in sync when you change it there).
- Deployment-level changes (plist edits, threshold changes, enable/disable)
  are changelogged HERE. Allowlist/policy changes belong to the canonical
  repo; at most reference them.
- Deletion policy lives in the canonical repo's README. Key invariants that
  must never be weakened silently: bin/obj deletion requires
  `git check-ignore`; whole-dir deletion requires the newest-file probe
  (dir mtime lies); artifacts matching is `-iname` (APFS is
  case-insensitive, qyl uses `Artifacts/`); Codex sessions cutoff is 14d by
  the owner's explicit 2026-07-25 decision.
