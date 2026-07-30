import Foundation

public enum TwitchLauncherError: LocalizedError {
    case invalidChannel(String)
    case invalidRefreshInterval
    case missingClientID
    case missingToken
    case missingChannels
    case invalidResponse
    case httpStatus(Int)
    case streamlinkNotFound
    case launchRateLimited
    case keychain(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidChannel(let channel):
            return "Invalid Twitch channel: \(channel)"
        case .invalidRefreshInterval:
            return "Refresh interval must be between 30 and 300 seconds."
        case .missingClientID:
            return "Add a Twitch Client ID in Settings."
        case .missingToken:
            return "Add a Twitch access token in Settings."
        case .missingChannels:
            return "Add at least one Twitch channel in Settings."
        case .invalidResponse:
            return "Twitch returned an invalid response."
        case .httpStatus(let status):
            return "Twitch returned HTTP \(status)."
        case .streamlinkNotFound:
            return "Streamlink is not installed or not executable."
        case .launchRateLimited:
            return nil
        case .keychain(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
