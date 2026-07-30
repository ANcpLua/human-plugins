# qyl-discord-sync

Mirrors selected upstream documentation directories into Discord as versioned
YAML attachments. Each message carries a full commit trailer, so the Discord
channel is the durable idempotency state and no database or broker is needed.

Copy `config/sources.example.json` from the installed release to
`~/.config/human-plugins/qyl-discord-sync.json`, then replace channel IDs:

```bash
qyl-discord-sync check-config
qyl-discord-sync sync --dry-run
qyl-discord-sync sync
```

The attachment is deterministic JSON, which is a valid YAML 1.2 subset. The
tool uses only Python's standard library and Git. On macOS it reads
`DISCORD_BOT_TOKEN` from the current user's Keychain; Linux reads it from the
environment. `GITHUB_TOKEN` or `GH_TOKEN` is optional for higher API limits.

The packaged launchd agent and systemd timer run daily at 09:30. Actual channel
IDs and tokens are local configuration and never enter the public repository.
