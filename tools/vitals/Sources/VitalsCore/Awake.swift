/// Lid, power and display facts the awake policy decides on. Read by the
/// kernel every tick; pure here.
public struct PowerContext: Sendable, Equatable, Codable {
    public enum Source: String, Sendable, Codable {
        case ac
        case battery
        case unknown
    }

    /// `AppleClamshellState`: the lid is physically closed.
    public let lidClosed: Bool
    /// `AppleClamshellCausesSleep`: closing the lid sleeps the Mac. macOS
    /// clears it on AC with an external display; on battery it is set and
    /// no unprivileged assertion can override it.
    public let lidClosesSleep: Bool
    public let source: Source
    public let externalDisplays: Int

    public init(lidClosed: Bool, lidClosesSleep: Bool, source: Source, externalDisplays: Int) {
        self.lidClosed = lidClosed
        self.lidClosesSleep = lidClosesSleep
        self.source = source
        self.externalDisplays = externalDisplays
    }
}

/// What the user asked for. Persisted, re-applied on every tick, so a
/// restart of Vitals re-establishes the same assertions instead of
/// dropping the external display.
public enum AwakeMode: String, Sendable, CaseIterable, Codable {
    case off
    /// Hold system and display awake unconditionally.
    case always
    /// Hold only while the lid is closed: the clamshell case.
    case lidClosed
    /// Hold only while an external display is attached.
    case externalDisplay

    public var title: String {
        switch self {
        case .off: "Off"
        case .always: "Always"
        case .lidClosed: "While the lid is closed"
        case .externalDisplay: "While an external display is attached"
        }
    }
}

public struct AwakeDecision: Sendable, Equatable {
    /// Hold `PreventUserIdleSystemSleep`.
    public let holdSystem: Bool
    /// Hold `PreventUserIdleDisplaySleep`.
    public let holdDisplay: Bool
    /// One line for the menu: what is held and why, or why it cannot work.
    public let reason: String
    /// True when the mode wants to hold but the OS will sleep anyway.
    public let warning: Bool

    public init(holdSystem: Bool, holdDisplay: Bool, reason: String, warning: Bool) {
        self.holdSystem = holdSystem
        self.holdDisplay = holdDisplay
        self.reason = reason
        self.warning = warning
    }

    public var holdsAnything: Bool { holdSystem || holdDisplay }
}

public enum Awake {
    public static func decide(mode: AwakeMode, context: PowerContext) -> AwakeDecision {
        let wants: Bool
        switch mode {
        case .off: wants = false
        case .always: wants = true
        case .lidClosed: wants = context.lidClosed
        case .externalDisplay: wants = context.externalDisplays > 0
        }
        guard wants else {
            return AwakeDecision(
                holdSystem: false, holdDisplay: false,
                reason: mode == .off ? "off" : "idle · \(describe(context))",
                warning: false
            )
        }
        // Assertions stop idle sleep. They do not stop lid-close sleep on
        // battery: that needs root (`pmset disablesleep`), which Vitals does
        // not have. Say so instead of pretending.
        let lidRisk = context.lidClosesSleep && context.source != .ac
        return AwakeDecision(
            holdSystem: true,
            holdDisplay: true,
            reason: lidRisk
                ? "holding · \(describe(context)) · lid close will still sleep on battery"
                : "holding · \(describe(context))",
            warning: lidRisk
        )
    }

    public static func describe(_ context: PowerContext) -> String {
        var parts = [context.lidClosed ? "lid closed" : "lid open"]
        switch context.source {
        case .ac: parts.append("AC")
        case .battery: parts.append("battery")
        case .unknown: break
        }
        parts.append(context.externalDisplays == 1 ? "1 external display" : "\(context.externalDisplays) external displays")
        return parts.joined(separator: " · ")
    }
}
