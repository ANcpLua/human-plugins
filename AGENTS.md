# Agent contract

`human-plugins` is the only source of truth for the host tools under `tools/`.
Every tool directory is independently understandable and contains exactly one
machine-readable `tool.json`, a README, a changelog, source, tests, and service
templates where applicable.

## Change path

1. Read the target `tool.json` and only the source it names.
2. Make the smallest coherent change. Breaking obsolete behavior is allowed.
3. Delete replaced code; Git history is the archive. Never create `legacy/`,
   `stale/`, compatibility shims, or duplicate implementations.
4. Run `./toolctl catalog --write`.
5. Run `python3 -m unittest discover -s tests -v` and
   `./toolctl validate`.
6. Run `./toolctl verify --tool <id> --platform <platform>`.

`tool.json` owns the CI runner, argv-only commands, packaged payload, stable
links, services, and installed health checks. Do not duplicate those facts in a
workflow or hand-edit `catalog.json`.

## Boundaries

- Commit source, deterministic build instructions, tests, and example config.
- Never commit tokens, user-specific IDs, notification topics, generated apps,
  build output, or local state.
- Runtime configuration lives under `~/.config/human-plugins/`.
- Packages may install only under the user home. Privileged installers and
  public self-hosted runners are out of scope.
- A release is usable only after package smoke, isolated deploy, health, and
  rollback all pass. GitHub attestation and SHA-256 verification are mandatory
  for remote updates.
