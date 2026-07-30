# airpods-mic-guard

Event-driven macOS daemon that keeps AirPods in hi-fi A2DP while listening and
yields the microphone during real calls.

Canonical source and deployment record:
[ANcpLua/human-plugins/tools/airpods-mic-guard](https://github.com/ANcpLua/human-plugins/tree/main/tools/airpods-mic-guard).

## The forever-lasting problem

Bluetooth cannot do hi-fi output (A2DP) and microphone input simultaneously on
AirPods. When macOS makes AirPods the default *input* while nothing is using
the mic, the whole link degrades to HFP "phone call" quality for no reason.
During an actual call, the AirPods mic is wanted — the guard must not fight it.

## The simplest solution (until proven wrong)

A resident daemon (`src/airpods-mic-guardd.swift`, single file, CoreAudio +
Foundation only) that sleeps in a run loop and is woken by `coreaudiod` only
when something relevant changes:

| Event | Source |
|---|---|
| default input device changed | `kAudioHardwarePropertyDefaultInputDevice` listener |
| default output device changed | `kAudioHardwarePropertyDefaultOutputDevice` listener |
| device list changed (AirPods (dis)connect) | `kAudioHardwarePropertyDevices` listener |
| an app opened/closed the mic stream (call start/end) | `kAudioDevicePropertyDeviceIsRunningSomewhere` listener on the current default input (re-bound whenever default input changes) |

On every wake, one pure decision:

1. AirPods NOT both default input and output → do nothing.
2. Kill switch `~/.airpods-guard-off` exists → do nothing.
3. Some app owns the mic stream (`DeviceIsRunningSomewhere`) → on a call, do nothing.
4. Otherwise arm a **one-shot 15 s grace timer**. If the state still holds when
   it fires, move default input to the built-in mic (else first non-AirPods
   input). AirPods snap back to A2DP.

The grace window absorbs blips (AirPods re-connecting mid-call drops the mic
stream for a moment) so the mic is never yanked away during a live call.
Detection is by hardware stream ownership, never by audio content — apps hold
the mic stream open for the whole call even while muted.

Zero polling, zero timers at rest, ~11 MB RSS, 0% CPU idle.

## Deploy

```sh
make install    # build, replace launchd job, verify
make status     # launchd state + last log lines
make uninstall
```

launchd: `launchd/com.ancplua.airpods-mic-guard.plist` — `KeepAlive`, no
`StartInterval`. Log: `~/Library/Logs/airpods-mic-guard.log`.

## History

v1 (retired 2026-07-10, preserved in `legacy/`) was a shell script spawned by
launchd every 5 s (`StartInterval 5`) calling `SwitchAudioSource` plus a
`mic-active` Swift helper binary, with a 3-poll grace counter in a temp file.
Functionally identical; replaced because polling violates the sleep-until-event
doctrine. v2 absorbs `mic-active` as a property listener.

See [CLAUDE.md](CLAUDE.md) and [CHANGELOG.md](CHANGELOG.md).
