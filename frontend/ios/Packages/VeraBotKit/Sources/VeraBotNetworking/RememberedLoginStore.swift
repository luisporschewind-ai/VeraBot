import Foundation
import Security

public struct RememberedLogin: Codable, Sendable {
    public let identifier: String
    public let password: String
    public let isPhone: Bool

    public init(identifier: String, password: String, isPhone: Bool) {
        self.identifier = identifier
        self.password = password
        self.isPhone = isPhone
    }
}

/// Last successful credentials for each server, stored only in this device's Keychain.
/// Separate from session tokens so signing out can still restore the login form.
public struct RememberedLoginStore: Sendable {
    private let service: String

    public init(service: String = "com.verabot.app.remembered-login") {
        self.service = service
    }

    private func query(server: String) -> [String: Any] {
        let account = server.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account]
    }

    public func load(server: String) -> RememberedLogin? {
        var q = query(server: server)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(RememberedLogin.self, from: data)
    }

    @discardableResult
    public func save(_ login: RememberedLogin, server: String) -> Bool {
        guard let data = try? JSONEncoder().encode(login) else { return false }
        let q = query(server: server)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var add = q
        add.merge(attributes) { $1 }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func remove(server: String) -> Bool {
        let status = SecItemDelete(query(server: server) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
