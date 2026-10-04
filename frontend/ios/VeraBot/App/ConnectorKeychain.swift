import Foundation
import Security

/// 连接器令牌（GitHub PAT 等）的 Keychain 暂存，与登录令牌（KeychainStore）分开的 service。
/// 只在上传前暂存：上传成功后删除（D3，后端加密副本是唯一持久副本）；失败时保留，供重试或删除。
/// 仅本机、解锁时可读，不进 iCloud。
enum ConnectorKeychain {
    private static let service = "com.verabot.app.connector"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// account 为 "<user_id>:<plugin_id>"
    static func account(userID: Int?, pluginID: String) -> String { "\(userID ?? 0):\(pluginID)" }

    @discardableResult
    static func stage(_ token: String, account: String) -> Bool {
        remove(account: account)
        var add = query(account)
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func remove(account: String) -> Bool {
        let status = SecItemDelete(query(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
