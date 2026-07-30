import Darwin
import VitalsCore
import VitalsKernel

// Proves the name memoization: capture A warms the cache, capture B must not
// re-read (no proc_name refetches beyond newborn pids) and must hand back the
// very same String storage capture A produced. CLT-only machines have no
// XCTest/swift-testing, so this is a plain executable: swift run selftest

func fail(_ message: String) -> Never {
    print("FAIL  \(message)")
    exit(1)
}

guard case let .success(first) = Sampler.capture() else { fail("capture A errored") }
let fetchesAfterA = Sampler.nameFetches.withLock { $0 }
guard case let .success(second) = Sampler.capture() else { fail("capture B errored") }
let refetched = Sampler.nameFetches.withLock { $0 } - fetchesAfterA

print("ok    capture A: \(first.processes.count) processes, \(fetchesAfterA) name fetches")
print("ok    capture B: \(second.processes.count) processes, \(refetched) name fetches")

guard second.processes.count > 100 else { fail("implausibly few processes sampled") }
guard refetched < second.processes.count / 10 else {
    fail("capture B re-read \(refetched) names — memoization not effective")
}

// Object identity: only observable for heap-backed strings; names within
// Swift's 15-byte small-string limit live inline and never allocate.
let firstNames = Dictionary(
    first.processes.map { ($0.pid, $0.name) },
    uniquingKeysWith: { name, _ in name }
)
var checked = 0
var shared = 0
for process in second.processes where process.name.utf8.count > 15 {
    guard var nameA = firstNames[process.pid] else { continue }
    var nameB = process.name
    let baseA = nameA.withUTF8 { UInt(bitPattern: $0.baseAddress) }
    let baseB = nameB.withUTF8 { UInt(bitPattern: $0.baseAddress) }
    checked += 1
    if baseA == baseB { shared += 1 }
}

guard checked > 0 else { fail("no heap-backed names to compare") }
guard shared == checked else {
    fail("identity: only \(shared)/\(checked) names share storage — copies were made")
}
print("ok    identity: \(shared)/\(checked) heap-backed names are the same object as capture A's")

func process(_ cpu: Double, name: String = "worker") -> ProcessView {
    ProcessView(
        pid: 42,
        ppid: 1,
        name: name,
        cpuPercent: cpu,
        footprintBytes: 1,
        residentBytes: 1
    )
}

var smoother = ProcessCPUSmoother(response: 0.3)
let baseline = smoother.smooth([process(10)])[0].cpuPercent!
let burst = smoother.smooth([process(110)])[0].cpuPercent!
let recovery = smoother.smooth([process(10)])[0].cpuPercent!
guard baseline == 10 else { fail("smoother changed its baseline") }
guard abs(burst - 40) < 0.001 else { fail("smoother did not damp a one-sample burst") }
guard abs(recovery - 31) < 0.001 else { fail("smoother did not decay predictably") }

var multicore = ProcessCPUSmoother(response: 0.3)
guard multicore.smooth([process(180)])[0].cpuPercent == 180 else {
    fail("smoother capped a valid multicore value")
}

_ = smoother.smooth([])
guard smoother.smooth([process(90)])[0].cpuPercent == 90 else {
    fail("smoother retained a terminated process")
}
guard smoother.smooth([process(120, name: "replacement")])[0].cpuPercent == 120 else {
    fail("smoother mixed different process identities")
}
print("ok    process CPU smoothing dampens bursts without capping multicore usage")
print("PASS  memoization verified: nothing re-read")
