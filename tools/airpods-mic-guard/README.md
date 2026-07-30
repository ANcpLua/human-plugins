# airpods-mic-guard

Event-driven CoreAudio daemon for macOS. When AirPods are both the default input
and output but no process owns the microphone, it waits 15 seconds and moves
input to a built-in fallback. Active calls are never interrupted.

```bash
airpods-mic-guardd --self-test
touch ~/.airpods-guard-off
```

The launchd service and complete delivery contract are in `tool.json`.
