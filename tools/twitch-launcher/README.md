# twitch-launcher

A native macOS app that shows configured Twitch channels and opens any stream
with Streamlink. API credentials are edited in the app; the Client ID and
channel list live in `~/.config/human-plugins/twitch-launcher.json`, while the
access token stays in the macOS Keychain.

The app requires macOS 14 or newer and an executable `streamlink` on `PATH` or
in a standard Homebrew location:

```bash
brew install streamlink
open ~/Applications/TwitchLauncher.app
```

The canonical source is a Swift package. CI builds the native app bundle,
runs model and packaged self-tests, verifies its ad-hoc signature, installs it
atomically, checks health, and exercises rollback. The old Tauri/React scaffold
and macOS 26-only prototype are intentionally not carried forward.
