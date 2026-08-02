# Changelog — home-guard

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Newest entry first.

## Unreleased

### Added
- Initial release: moves every top-level `$HOME` entry that is neither a
  directory, a dotfile, nor an allowlisted AI instruction file into
  `~/REVIEW-REQUIRED`, with collision-safe names and a signal-only log.
- launchd agent triggered by `WatchPaths` on the home directory with a
  RunAtLoad sweep and 30s throttle.
- Sweep-and-noop test, packaged smoke run on an empty home, and an installed
  health check that performs a real sweep.
