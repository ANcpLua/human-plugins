# vitals — agent guidance

Read root `../../CLAUDE.md` first (mandatory drift check). History in
[CHANGELOG.md](CHANGELOG.md), newest entry first.

**Federated tool**: source of truth for code is
`~/RiderProjects/qyl-workspace/vitals` (github.com/ANcpLua/vitals). Code
changes happen THERE, with that repo's own history. This entry owns only the
deployment record.

Rules:
- The repo copy `launchd/dev.ancplua.vitals.plist` must stay byte-identical to
  `~/Library/LaunchAgents/dev.ancplua.vitals.plist` AND to the canonical
  repo's `dev.ancplua.vitals.plist` (drift-check compares the installed one).
  If the plist changes in the canonical repo, update the installed copy and
  this repo copy in the same operation, with a new topmost changelog entry
  here.
- Deployment-level changes (plist edits, app reinstalls at a new version,
  enable/disable as login item) are changelogged HERE. Code changes are not —
  they belong to the canonical repo; at most reference the version bump.
- Useful for agents host-wide: `vitals json` gives a machine-readable
  CPU/memory/disk snapshot; `vitals predict <pid>` estimates reclaim from
  killing a process tree.
