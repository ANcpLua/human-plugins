import Foundation
import TwitchCore

@main
enum TwitchLauncherSelfTest {
    static func main() {
        do {
            try run()
            print("twitch-launcher self-test ok")
        } catch {
            FileHandle.standardError.write(
                Data("twitch-launcher: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }
    }

    private static func run() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                FileHandle.standardError.write(
                    Data("twitch-launcher cleanup: \(error.localizedDescription)\n".utf8)
                )
            }
        }
        let url = directory.appendingPathComponent("config.json")
        let configuration = try AppConfiguration(
            clientID: "client",
            channels: ["Example", "example", "Other_Channel"],
            refreshInterval: 60
        ).normalized()
        try ConfigurationStore.save(configuration, to: url)
        let loaded = try ConfigurationStore.load(from: url)
        guard loaded.channels == ["Example", "Other_Channel"] else {
            throw TwitchLauncherError.invalidResponse
        }
        let endpoint = try TwitchClient.endpoint(channels: loaded.channels)
        guard endpoint.query?.contains("user_login=Example") == true else {
            throw TwitchLauncherError.invalidResponse
        }
    }
}
