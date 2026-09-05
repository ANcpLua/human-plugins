import CoreGraphics
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import VitalsCore

/// Lid, power source and display facts from IOKit and CoreGraphics. No
/// process spawns; every call is a registry or framework read.
public enum PowerSampler {
    public static func context() -> PowerContext {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { if root != 0 { IOObjectRelease(root) } }
        return PowerContext(
            lidClosed: bool(root, "AppleClamshellState"),
            lidClosesSleep: bool(root, "AppleClamshellCausesSleep"),
            source: source(),
            externalDisplays: externalDisplays()
        )
    }

    static func bool(_ service: io_service_t, _ key: String) -> Bool {
        guard service != 0,
              let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                  .takeRetainedValue()
        else { return false }
        return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
    }

    static func source() -> PowerContext.Source {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else { return .unknown }
        switch type {
        case kIOPMACPowerKey: return .ac
        case kIOPMBatteryPowerKey, kIOPMUPSPowerKey: return .battery
        default: return .unknown
        }
    }

    static func externalDisplays() -> Int {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return 0 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return 0 }
        return displays.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.count
    }
}

/// Owns the two IOKit power assertions. Idempotent: `apply` creates what
/// the decision wants and releases what it no longer wants, so calling it
/// every tick costs nothing when nothing changed. Assertions die with the
/// process; that is why the policy is persisted and re-applied at launch.
@MainActor
public final class AwakeAssertions {
    private var system: IOPMAssertionID = 0
    private var display: IOPMAssertionID = 0
    public private(set) var lastError: String?

    public init() {}

    public var holdsSystem: Bool { system != 0 }
    public var holdsDisplay: Bool { display != 0 }

    public func apply(_ decision: AwakeDecision) {
        lastError = nil
        toggle(&system, kIOPMAssertionTypePreventUserIdleSystemSleep as String, wanted: decision.holdSystem)
        toggle(&display, kIOPMAssertionTypePreventUserIdleDisplaySleep as String, wanted: decision.holdDisplay)
    }

    public func releaseAll() {
        apply(AwakeDecision(holdSystem: false, holdDisplay: false, reason: "off", warning: false))
    }

    private func toggle(_ id: inout IOPMAssertionID, _ type: String, wanted: Bool) {
        if wanted, id == 0 {
            var created: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Vitals stay awake" as CFString,
                &created
            )
            if result == kIOReturnSuccess {
                id = created
            } else {
                lastError = "\(type) failed: IOReturn \(result)"
            }
        } else if !wanted, id != 0 {
            IOPMAssertionRelease(id)
            id = 0
        }
    }
}
