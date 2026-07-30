import AppKit
import Foundation
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

case "disk":
    let path = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) ?? ProcessInfo.processInfo.environment["HOME"] ?? "/"
    let asJson = arguments.contains("--json")
    switch Scanner.scan(root: path, top: 25) {
    case let .success(scan):
        asJson ? Printer.json(scan) : Printer.diskScan(scan)
    case let .failure(error):
        Printer.failure(error)
        exit(1)
    }

case "watch":
    let interval = arguments.dropFirst().first.flatMap(Double.init) ?? 2.0
    let diskGB = arguments.dropFirst(2).first.flatMap(Double.init) ?? 10.0
    let thresholds = Thresholds(
        diskFreeBytes: UInt64(diskGB * 1_073_741_824.0),
        diskRecoverBytes: UInt64((diskGB + 2.0) * 1_073_741_824.0)
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

case "bar":
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let controller = MenuBarController()
    controller.start()
    application.run()

default:
    Printer.err("usage: vitals [snapshot | json | predict <pid> | watch [s] [diskGB] | disk [path] | bar]")
    exit(2)
}
