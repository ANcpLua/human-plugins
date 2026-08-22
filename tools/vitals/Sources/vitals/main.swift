import AppKit
import Foundation
import VitalsClaude
import VitalsCore
import VitalsKernel

func observe(intervalMicros: UInt32) -> Result<Snapshot, MetricsError> {
    Sampler.capture().flatMap { first in
        usleep(intervalMicros)
        return Sampler.capture().map { second in
            Derive.snapshot(previous: first, current: second)
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let mode = arguments.first ?? (isatty(FileHandle.standardInput.fileDescriptor) != 0 ? "snapshot" : "bar")

switch mode {
case "snapshot":
    switch observe(intervalMicros: 300_000) {
    case let .success(snapshot):
        Printer.snapshot(snapshot, top: 20)
    case let .failure(error):
        Printer.failure(error)
        exit(1)
    }

case "predict":
    guard let raw = arguments.dropFirst().first, let pid = Int32(raw) else {
        Printer.err("usage: vitals predict <pid>")
        exit(2)
    }
    switch observe(intervalMicros: 300_000) {
    case let .success(snapshot):
        guard let prediction = Derive.killPrediction(pid: pid, in: snapshot) else {
            Printer.err("no such pid \(pid)")
            exit(1)
        }
        Printer.prediction(prediction, in: snapshot)
    case let .failure(error):
        Printer.failure(error)
        exit(1)
    }

case "json":
    switch observe(intervalMicros: 300_000) {
    case let .success(snapshot):
        Printer.json(snapshot)
    case let .failure(error):
        Printer.failure(error)
        exit(1)
    }

case "watch":
    let interval = arguments.dropFirst().first.flatMap(Double.init) ?? 2.0
    let diskGB = arguments.dropFirst(2).first.flatMap(Double.init) ?? 10.0
    let thresholds = Thresholds(
        diskAvailableBytes: UInt64(diskGB * 1_000_000_000.0),
        diskRecoverAvailableBytes: UInt64((diskGB + 2.0) * 1_000_000_000.0)
    )
    var state = AlarmState()
    while true {
        switch observe(intervalMicros: 300_000) {
        case let .success(snapshot):
            let decision = Derive.evaluateAlarms(snapshot: snapshot, thresholds: thresholds, previous: state)
            state = decision.state
            Printer.dashboard(snapshot, alarms: state, top: 15)
            for kind in decision.triggered {
                Notifier.deliver(kind, snapshot: snapshot)
            }
        case let .failure(error):
            Printer.failure(error)
            exit(1)
        }
        let remaining = interval - 0.3
        if remaining > 0 {
            usleep(UInt32(remaining * 1_000_000.0))
        }
    }

case "claude":
    // Headless view of the menu's Claude section: status, usage, local sessions.
    // Exercises the Keychain path exactly as the menu bar does, so a prompt
    // here means the menu bar would prompt too.
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        let telemetry = await ClaudeTelemetryClient().fetch()
        Printer.out("status    \(telemetry.health.label)  \(telemetry.health.detail)")
        if let message = telemetry.usage.unavailableMessage {
            Printer.out("usage     \(message)")
        }
        for row in telemetry.usage.rows {
            Printer.out("usage     \(row.label.padding(toLength: 22, withPad: " ", startingAt: 0))\(row.detail)")
        }
        let sessions = ClaudeSessionStore.load()
        Printer.out("sessions  \(sessions.sessions.count) local · \(sessions.busyCount) busy  (\(ClaudeHome().sessionsDirectory.path))")
        for session in sessions.sessions {
            Printer.out("  \(session.status.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)) \(session.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(Format.age(since: session.startedAt).padding(toLength: 9, withPad: " ", startingAt: 0)) \(session.abbreviatedCwd())")
        }
        semaphore.signal()
    }
    semaphore.wait()

case "bar":
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let controller = MenuBarController()
    controller.start()
    application.run()

default:
    Printer.err("usage: vitals [snapshot | json | predict <pid> | watch [s] [diskGB] | claude | bar]")
    exit(2)
}
