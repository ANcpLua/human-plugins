import CryptoKit
import Foundation

public final class ClaudeKeychainAuthorization {
    private static let defaultsKey = "claudeKeychainAuthorizedBinarySHA256"

    private let defaults: UserDefaults
    private let fingerprint: String?

    public init(
        defaults: UserDefaults = .standard,
        executableURL: URL? = Bundle.main.executableURL
    ) {
        self.defaults = defaults
        fingerprint = executableURL.flatMap(Self.fingerprint)
    }

    public var permitsBackgroundAccess: Bool {
        guard let fingerprint else { return false }
        return defaults.string(forKey: Self.defaultsKey) == fingerprint
    }

    public func grant() {
        guard let fingerprint else { return }
        defaults.set(fingerprint, forKey: Self.defaultsKey)
    }

    public func revoke() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private static func fingerprint(_ executableURL: URL) -> String? {
        guard let data = try? Data(
            contentsOf: executableURL,
            options: .mappedIfSafe
        ) else {
            return nil
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
