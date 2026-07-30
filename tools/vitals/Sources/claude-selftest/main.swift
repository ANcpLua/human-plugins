import Foundation
import VitalsClaude

var failures: [String] = []

@MainActor
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures.append(message)
    }
}

func snapshot(
    health: ClaudeHealthLevel = .operational,
    utilization: Double = 10
) -> ClaudeTelemetrySnapshot {
    ClaudeTelemetrySnapshot(
        health: ClaudeHealth(
            level: health,
            label: health == .operational ? "OPERATIONAL" : "DEGRADED",
            detail: "Claude API"
        ),
        usage: .available([
            ClaudeUsageRow(
                id: "weekly_all",
                label: "Weekly · all models",
                fraction: min(utilization / 100, 1),
                detail: "\(Int(utilization))%",
                utilization: utilization
            )
        ]),
        capturedAt: Date(timeIntervalSince1970: 0)
    )
}

do {
    let usageData = Data(
        """
        {
          "limits": [
            {
              "kind": "weekly_scoped",
              "percent": 74,
              "resets_at": "2026-08-01T08:00:00.000000+00:00",
              "scope": {"model": {"display_name": "Fable"}}
            },
            {
              "kind": "future_limit",
              "percent": 99,
              "resets_at": null,
              "scope": null
            },
            {
              "kind": "session",
              "percent": 2,
              "resets_at": "2026-07-29T18:00:00.000000+00:00",
              "scope": null
            },
            {
              "kind": "weekly_all",
              "percent": 81,
              "resets_at": "2026-08-01T08:00:00.000000+00:00",
              "scope": null
            }
          ]
        }
        """.utf8
    )
    guard let now = ISO8601DateFormatter().date(
        from: "2026-07-29T14:00:00Z"
    ) else {
        throw SelftestError.invalidFixtureDate
    }
    let rows = try ClaudeUsageParser.parse(usageData, now: now)
    expect(
        rows.map(\.label) == [
            "5-hour limit",
            "Weekly · all models",
            "Weekly · Fable"
        ],
        "usage rows are not in the expected display order"
    )
    expect(
        rows.map(\.fraction) == [0.02, 0.81, 0.74],
        "usage fractions were not normalized"
    )
    expect(
        rows.map(\.detail) == [
            "2% · resets 4h",
            "81% · resets 3d",
            "74% · resets 3d"
        ],
        "usage reset details were not formatted correctly"
    )

    let operational = try ClaudeStatusParser.parse(Data(
        """
        {
          "status": {"indicator": "none", "description": "All Systems Operational"},
          "components": [{"name": "Claude API", "status": "operational"}]
        }
        """.utf8
    ))
    let degraded = try ClaudeStatusParser.parse(Data(
        """
        {
          "status": {"indicator": "minor", "description": "Partial degradation"},
          "components": [
            {"name": "Claude API", "status": "degraded_performance"},
            {"name": "Claude Code", "status": "operational"}
          ]
        }
        """.utf8
    ))
    expect(
        operational.level == .operational
            && operational.label == "OPERATIONAL",
        "operational status was not mapped correctly"
    )
    expect(
        degraded.level == .degraded
            && degraded.label == "DEGRADED"
            && degraded.detail == "Claude API",
        "degraded status did not identify the affected component"
    )

    var state = ClaudeAlertState()
    var decision = ClaudeAlerts.evaluate(
        snapshot: snapshot(utilization: 74),
        previous: state
    )
    expect(decision.triggered.isEmpty, "initial usage emitted an alert")
    state = decision.state

    decision = ClaudeAlerts.evaluate(
        snapshot: snapshot(utilization: 81),
        previous: state
    )
    expect(
        decision.triggered.map(\.message) == [
            "Weekly · all models reached 75%"
        ],
        "75% usage edge did not emit exactly once"
    )
    state = decision.state

    decision = ClaudeAlerts.evaluate(
        snapshot: snapshot(utilization: 82),
        previous: state
    )
    expect(decision.triggered.isEmpty, "usage alert repeated above its edge")
    state = decision.state

    decision = ClaudeAlerts.evaluate(
        snapshot: snapshot(utilization: 96),
        previous: state
    )
    expect(
        decision.triggered.map(\.message) == [
            "Weekly · all models reached 90%"
        ],
        "highest crossed usage edge was not selected"
    )
    state = decision.state

    decision = ClaudeAlerts.evaluate(
        snapshot: snapshot(utilization: 101),
        previous: state
    )
    expect(
        decision.triggered.map(\.message) == [
            "Weekly · all models reached 100%"
        ],
        "100% usage edge did not emit exactly once"
    )

    let initialHealth = ClaudeAlerts.evaluate(
        snapshot: snapshot(health: .operational),
        previous: ClaudeAlertState()
    )
    let degradedHealth = ClaudeAlerts.evaluate(
        snapshot: snapshot(health: .degraded),
        previous: initialHealth.state
    )
    let recoveredHealth = ClaudeAlerts.evaluate(
        snapshot: snapshot(health: .operational),
        previous: degradedHealth.state
    )
    expect(initialHealth.triggered.isEmpty, "initial health emitted an alert")
    expect(
        degradedHealth.triggered.map(\.title) == [
            "Vitals · Claude status"
        ],
        "health degradation did not emit an alert"
    )
    expect(
        recoveredHealth.triggered.isEmpty,
        "health recovery emitted an unwanted alert"
    )
    let authorizationRequired = ClaudeUsageState.authorizationRequired
    expect(
        authorizationRequired.requiresAuthorization
            && authorizationRequired.rows.isEmpty
            && authorizationRequired.unavailableMessage
                == "Enable Claude usage in Keychain",
        "Keychain authorization state is not explicit"
    )

    let defaultsName = "vitals-claude-selftest-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: defaultsName)!
    defer {
        defaults.removePersistentDomain(forName: defaultsName)
    }
    let executable = FileManager.default.temporaryDirectory
        .appendingPathComponent(defaultsName)
    defer {
        try? FileManager.default.removeItem(at: executable)
    }
    try Data("first build".utf8).write(to: executable)
    let firstBuild = ClaudeKeychainAuthorization(
        defaults: defaults,
        executableURL: executable
    )
    expect(
        !firstBuild.permitsBackgroundAccess,
        "unknown binary inherited Keychain authorization"
    )
    firstBuild.grant()
    expect(
        firstBuild.permitsBackgroundAccess,
        "authorized binary fingerprint was not persisted"
    )
    try Data("second build".utf8).write(to: executable)
    let secondBuild = ClaudeKeychainAuthorization(
        defaults: defaults,
        executableURL: executable
    )
    expect(
        !secondBuild.permitsBackgroundAccess,
        "changed binary inherited stale Keychain authorization"
    )
} catch {
    failures.append("selftest threw: \(error)")
}

if failures.isEmpty {
    print("claude selftest: ok")
    exit(0)
}

for failure in failures {
    FileHandle.standardError.write(Data("claude selftest: \(failure)\n".utf8))
}
exit(1)

enum SelftestError: Error {
    case invalidFixtureDate
}
