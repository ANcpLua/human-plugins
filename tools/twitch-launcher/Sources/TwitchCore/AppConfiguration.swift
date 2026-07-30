import Foundation

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var clientID: String
    public var channels: [String]
    public var refreshInterval: Int

    public init(
        clientID: String = "",
        channels: [String] = [],
        refreshInterval: Int = 60
    ) {
        self.clientID = clientID
        self.channels = channels
        self.refreshInterval = refreshInterval
    }

    public func normalized() throws -> AppConfiguration {
        guard (30...300).contains(refreshInterval) else {
            throw TwitchLauncherError.invalidRefreshInterval
        }
        var seen: Set<String> = []
        var normalizedChannels: [String] = []
        for rawChannel in channels {
            let channel = rawChannel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard channel.range(
                of: #"^[A-Za-z0-9_]{1,25}$"#,
                options: .regularExpression
            ) != nil else {
                throw TwitchLauncherError.invalidChannel(rawChannel)
            }
            if seen.insert(channel.lowercased()).inserted {
                normalizedChannels.append(channel)
            }
        }
        return AppConfiguration(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            channels: normalizedChannels,
            refreshInterval: refreshInterval
        )
    }

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case channels
        case refreshInterval = "refresh_interval"
    }
}

public enum ConfigurationStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/human-plugins", isDirectory: true)
            .appendingPathComponent("twitch-launcher.json")
    }

    public static func load(from url: URL = defaultURL) throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppConfiguration()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfiguration.self, from: data).normalized()
    }

    public static func save(
        _ configuration: AppConfiguration,
        to url: URL = defaultURL
    ) throws {
        let normalized = try configuration.normalized()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(normalized)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
