public struct Thresholds: Sendable, Equatable {
    public let diskFreeBytes: UInt64
    public let diskRecoverBytes: UInt64

    public init(diskFreeBytes: UInt64, diskRecoverBytes: UInt64) {
        self.diskFreeBytes = diskFreeBytes
        self.diskRecoverBytes = diskRecoverBytes
    }
}

public enum AlarmKind: String, Sendable, Equatable {
    case diskLow
    case memoryRed
}

public struct AlarmState: Sendable, Equatable {
    public let diskFiring: Bool
    public let memoryFiring: Bool

    public init(diskFiring: Bool = false, memoryFiring: Bool = false) {
        self.diskFiring = diskFiring
        self.memoryFiring = memoryFiring
    }
}

public struct AlarmDecision: Sendable, Equatable {
    public let state: AlarmState
    public let triggered: [AlarmKind]

    public init(state: AlarmState, triggered: [AlarmKind]) {
        self.state = state
        self.triggered = triggered
    }
}

public extension Derive {
    static func evaluateAlarms(snapshot: Snapshot, thresholds: Thresholds, previous: AlarmState) -> AlarmDecision {
        let diskFiring = latch(
            firing: previous.diskFiring,
            trip: snapshot.disk.free < thresholds.diskFreeBytes,
            clear: snapshot.disk.free >= thresholds.diskRecoverBytes
        )
        let memoryFiring = latch(
            firing: previous.memoryFiring,
            trip: snapshot.memory.pressure == .red,
            clear: snapshot.memory.pressure == .green
        )
        var triggered: [AlarmKind] = []
        if diskFiring, !previous.diskFiring { triggered.append(.diskLow) }
        if memoryFiring, !previous.memoryFiring { triggered.append(.memoryRed) }
        return AlarmDecision(
            state: AlarmState(diskFiring: diskFiring, memoryFiring: memoryFiring),
            triggered: triggered
        )
    }

    private static func latch(firing: Bool, trip: Bool, clear: Bool) -> Bool {
        if trip { return true }
        if clear { return false }
        return firing
    }
}
