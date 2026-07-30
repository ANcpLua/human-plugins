import Foundation

@MainActor
public final class StreamLauncher {
    private var lastLaunch: [String: Date] = [:]
    private let cooldown: TimeInterval

    public init(cooldown: TimeInterval = 5) {
        self.cooldown = cooldown
    }

    public func launch(channel: String) throws {
        let key = channel.lowercased()
        if let previous = lastLaunch[key],
           Date().timeIntervalSince(previous) < cooldown
        {
            throw TwitchLauncherError.launchRateLimited
        }
        guard let executable = Self.findStreamlink() else {
            throw TwitchLauncherError.streamlinkNotFound
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["https://www.twitch.tv/\(channel)", "best"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        lastLaunch[key] = Date()
    }

    public static func findStreamlink(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/streamlink" }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/streamlink",
            "/usr/local/bin/streamlink",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/streamlink").path,
            "/usr/bin/streamlink",
        ])
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
}
