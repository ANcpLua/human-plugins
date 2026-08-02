# home-guard

Enforces the top-level `$HOME` invariant: everything directly in the home
directory must be a **directory**, a **dotfile**, or one of the allowlisted
**AI instruction files** (`AGENTS.md`, `CLAUDE.md`, `CLAUDE.local.md`,
`GEMINI.md`). Anything else — stray scripts, drafts, downloads, broken
symlinks — is moved to `~/REVIEW-REQUIRED` for manual triage.

Rationale: `~/.claude` and `~/.codex` are the highest-authority agent rule
roots and live at exactly this level; everything below inherits from them.
Loose files at the top level are either misplaced config or clutter, so the
guard makes the invariant self-maintaining.

## Behavior

- Never recurses; only direct children of `$HOME` are examined.
- Dotfiles and dot-directories are skipped by construction (default glob).
- Symlinks that resolve to directories count as directories and stay.
- Name collisions in `~/REVIEW-REQUIRED` get a timestamp+pid suffix.
- Moves are logged to `~/Library/Logs/home-guard.log`; no-op runs stay silent.
- Triggered by launchd `WatchPaths` on `$HOME` (plus a sweep at load);
  `ThrottleInterval` 30s absorbs event storms.

## Manual run

```sh
~/.local/bin/home-guardd
```

`HOME_GUARD_REVIEW_DIR` overrides the triage directory (used by tests).
