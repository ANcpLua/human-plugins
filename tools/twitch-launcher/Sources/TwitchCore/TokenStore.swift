import Foundation
import Security

public enum TokenStore {
    private static let service = "com.ancplua.TwitchLauncher"
    private static let account = "twitch-access-token"

    public static func load() throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return ""
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            throw TwitchLauncherError.keychain(status)
        }
        return token
    }

    public static func save(_ rawToken: String) throws {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if token.isEmpty {
            let status = SecItemDelete(key as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TwitchLauncherError.keychain(status)
            }
            return
        }
        let value: [CFString: Any] = [kSecValueData: Data(token.utf8)]
        let updateStatus = SecItemUpdate(
            key as CFDictionary,
            value as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw TwitchLauncherError.keychain(updateStatus)
        }
        var item = key
        item[kSecValueData] = Data(token.utf8)
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TwitchLauncherError.keychain(addStatus)
        }
    }
}
