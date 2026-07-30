import Foundation

public actor TwitchClient {
    private struct Response: Decodable {
        let data: [LiveStream]
    }

    private struct LiveStream: Decodable {
        let userLogin: String
        let userName: String
        let viewerCount: Int
        let gameName: String
        let title: String

        enum CodingKeys: String, CodingKey {
            case userLogin = "user_login"
            case userName = "user_name"
            case viewerCount = "viewer_count"
            case gameName = "game_name"
            case title
        }
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func endpoint(channels: [String]) throws -> URL {
        guard let base = URL(string: "https://api.twitch.tv/helix/streams"),
              var components = URLComponents(
                  url: base,
                  resolvingAgainstBaseURL: false
              )
        else {
            throw TwitchLauncherError.invalidResponse
        }
        components.queryItems = channels.map {
            URLQueryItem(name: "user_login", value: $0)
        }
        guard let url = components.url else {
            throw TwitchLauncherError.invalidResponse
        }
        return url
    }

    public func streams(
        channels: [String],
        clientID: String,
        token: String
    ) async throws -> [StreamInfo] {
        guard !clientID.isEmpty else {
            throw TwitchLauncherError.missingClientID
        }
        guard !token.isEmpty else {
            throw TwitchLauncherError.missingToken
        }
        guard !channels.isEmpty else {
            throw TwitchLauncherError.missingChannels
        }
        var live: [String: StreamInfo] = [:]
        for start in stride(from: 0, to: channels.count, by: 100) {
            let end = min(start + 100, channels.count)
            let batch = Array(channels[start..<end])
            var request = URLRequest(url: try Self.endpoint(channels: batch))
            request.setValue(clientID, forHTTPHeaderField: "Client-ID")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TwitchLauncherError.invalidResponse
            }
            guard http.statusCode == 200 else {
                throw TwitchLauncherError.httpStatus(http.statusCode)
            }
            let payload = try JSONDecoder().decode(Response.self, from: data)
            for stream in payload.data {
                live[stream.userLogin.lowercased()] = StreamInfo(
                    name: stream.userLogin,
                    displayName: stream.userName,
                    isOnline: true,
                    viewerCount: stream.viewerCount,
                    gameName: stream.gameName,
                    title: stream.title
                )
            }
        }
        return channels.map { channel in
            live[channel.lowercased()] ?? StreamInfo(name: channel)
        }
    }
}
