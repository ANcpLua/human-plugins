# forgejo-local-ci

Runs Forgejo and a containerized Actions runner entirely on the local Docker
network. Public GitHub workflows never receive access to the host Docker
daemon.

```bash
forgejo-local-ci bootstrap
forgejo-local-ci doctor
forgejo-local-ci dispatch
forgejo-local-ci poll
forgejo-local-ci import ~/src/project
forgejo-local-ci stop
```

Runtime data and generated secrets live outside release payloads under
`${XDG_STATE_HOME:-~/.local/state}/human-plugins/forgejo-local-ci`. Images are
pinned by digest. `stop` preserves state; the CLI deliberately has no command
that deletes volumes or credentials.

The runner executes repository workflows with a privileged Docker-in-Docker
sidecar. Treat imported workflows as code execution and import only repositories
you trust.
