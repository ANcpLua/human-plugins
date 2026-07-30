# Changelog — airpods-mic-guard

Format: [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/). Newest entry first.

## Unreleased

### Added
- Pure state-machine self-test, deterministic package, installed health check,
  and atomic rollback exercise.

### Removed
- The polling-era shell and helper sources. Git history remains the archive.

## [2.0.1] - 2026-07-30

### Changed
- README now identifies and links its canonical source location in the public
  human-plugins catalog; the repository-wide link-integrity gate validates it.

## [2.0.0] - 2026-07-10

### Changed
- Rewritten as an event-driven resident daemon (`src/airpods-mic-guardd.swift`).
  Sleeps in `CFRunLoopRun()`; woken by CoreAudio property listeners (default
  input/output changed, device list changed, mic stream ownership changed).
  Zero polling — replaces v1's launchd `StartInterval 5` spawn-every-5-seconds
  model (~17,280 spawns/day → ~dozens of event wakes/day, instant reaction).
- Grace window is now a one-shot 15 s `DispatchWorkItem` armed only in the bad
  state (was: 3 consecutive 5 s polls tracked in a temp file).
- launchd job switched to `KeepAlive` + `ThrottleInterval 10`, logs to
  `~/Library/Logs/airpods-mic-guard.log`.

### Added
- `Makefile` (`build` / `install` / `uninstall` / `status`).
- Structured decision logging (grace armed/cancelled with reason, switch
  performed with target device).

### Removed
- `~/.local/bin/airpods-mic-guard.sh`, `~/.local/bin/mic-active` (+ `.swift`)
  — deleted from the host; the daemon absorbs the mic-ownership check as a
  listener. Sources preserved in `legacy/`.

### Unchanged
- Decision logic and thresholds: AirPods must be both default input AND output;
  mic-idle detection via `kAudioDevicePropertyDeviceIsRunningSomewhere`; 15 s
  effective grace; kill switch `~/.airpods-guard-off`; fallback = built-in mic,
  else first non-AirPods input.

## [1.0.0] - 2026-07-08

### Added
- Initial shell-script implementation (`legacy/airpods-mic-guard.sh`): launchd
  `StartInterval 5` poll calling `SwitchAudioSource`, with `mic-active` Swift
  helper (`kAudioDevicePropertyDeviceIsRunningSomewhere`) and a 3-poll grace
  counter in `$TMPDIR/airpods-mic-guard.idlecount`. Documented retroactively
  at repo creation; entry reconstructed from file mtimes (Jul 8 2026).
