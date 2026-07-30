# opusbreak

Dependency-free Node CLI for Anthropic's public StatusPage. It refreshes a local
cache, renders compact human/model advisories, and describes incident timing
with an explicit Poisson-rate model.

```bash
opusbreak poll
opusbreak statusline
opusbreak advisory
opusbreak analyze --timezone Europe/Berlin
opusbreak self-test
```

The launchd job and systemd timer poll every five minutes. Cache state lives at
`~/.local/state/human-plugins/opusbreak.json`.
