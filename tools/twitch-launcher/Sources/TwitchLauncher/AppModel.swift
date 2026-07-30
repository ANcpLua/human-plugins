import Foundation
import TwitchCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var configuration: AppConfiguration
    @Published private(set) var token: String
    @Published private(set) var streams: [StreamInfo] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false

    private let client = TwitchClient()
    private let launcher = StreamLauncher()

    init() {
        var startupError: String?
        do {
            configuration = try ConfigurationStore.load()
        } catch {
            configuration = AppConfiguration()
            startupError = error.localizedDescription
        }
        do {
            token = try TokenStore.load()
        } catch {
            token = ""
            startupError = error.localizedDescription
        }
        errorMessage = startupError
    }

    var online: [StreamInfo] {
        streams.filter(\.isOnline)
    }

    var offline: [StreamInfo] {
        streams.filter { !$0.isOnline }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            streams = try await client.streams(
                channels: configuration.channels,
                clientID: configuration.clientID,
                token: token
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(
                    for: .seconds(configuration.refreshInterval)
                )
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            await refresh()
        }
    }

    func save(
        clientID: String,
        token: String,
        channelsText: String,
        refreshInterval: Int
    ) -> Bool {
        do {
            let channels = channelsText
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            let next = try AppConfiguration(
                clientID: clientID,
                channels: channels,
                refreshInterval: refreshInterval
            ).normalized()
            try ConfigurationStore.save(next)
            try TokenStore.save(token)
            configuration = next
            self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func launch(_ stream: StreamInfo) {
        do {
            try launcher.launch(channel: stream.name)
        } catch TwitchLauncherError.launchRateLimited {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
