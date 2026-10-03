import Foundation
import Security
import VeraBotNetworking

/// 访问令牌 + 刷新令牌存 Keychain（仅本机、首次解锁后可读，不进 iCloud 备份）。
enum KeychainStore {
    private static let service = "com.verabot.app.auth"
    private static let account = "tokens"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> AuthTokens? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    @discardableResult
    static func save(_ tokens: AuthTokens?) -> Bool {
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attrs) { $1 }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
