// 账号 v9（schema v9）：邮箱 + 密码、邮箱 + 验证码、手机号 + 密码；刷新令牌。字段与后端 api/schemas.py、
// services/auth.py 一一对应（契约测试 backend/scripts/test/auth_test.py AUTH-CONTRACT）。设计见 docs/design/AUTH_REFACTOR.md。
import Foundation

/// 登录 / 注册 / 刷新的响应。旧后端没有 refresh_token / expires_in，解码为 nil。
public struct AuthResponse: Codable, Sendable {
    public let token: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let user: User

    public init(token: String, refreshToken: String? = nil, expiresIn: Int? = nil, user: User) {
        self.token = token
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case token
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

/// POST /api/auth/login：identifier = 邮箱 / 手机号 / 用户名（demo 开发账号）。
public struct LoginRequest: Codable, Sendable {
    public let identifier: String
    public let password: String

    public init(identifier: String, password: String) {
        self.identifier = identifier
        self.password = password
    }

    enum CodingKeys: String, CodingKey {
        case identifier, password
    }
}

/// POST /api/auth/register：email 与 phone 二选一（nil 不编码）。
public struct RegisterRequest: Codable, Sendable {
    public let email: String?
    public let phone: String?
    public let password: String

    public init(email: String? = nil, phone: String? = nil, password: String) {
        self.email = email
        self.phone = phone
        self.password = password
    }

    enum CodingKeys: String, CodingKey {
        case email, phone, password
    }
}

/// POST /api/auth/email/send-code
public struct EmailCodeRequest: Codable, Sendable {
    public let email: String
    public init(email: String) { self.email = email }

    enum CodingKeys: String, CodingKey {
        case email
    }
}

/// POST /api/auth/email/login（邮箱还没有账号时后端会直接创建）
public struct EmailCodeLoginRequest: Codable, Sendable {
    public let email: String
    public let code: String
    public init(email: String, code: String) {
        self.email = email
        self.code = code
    }

    enum CodingKeys: String, CodingKey {
        case email, code
    }
}

/// POST /api/me/email/verify
public struct EmailVerifyRequest: Codable, Sendable {
    public let code: String
    public init(code: String) { self.code = code }

    enum CodingKeys: String, CodingKey {
        case code
    }
}

/// POST /api/auth/refresh、/api/auth/logout
public struct RefreshRequest: Codable, Sendable {
    public let refreshToken: String
    public init(refreshToken: String) { self.refreshToken = refreshToken }

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

/// 发验证码的结果：有效期与下次可发的秒数。
public struct CodeSentResponse: Codable, Sendable {
    public let ok: Bool
    public let expiresIn: Int?
    public let retryAfter: Int?

    enum CodingKeys: String, CodingKey {
        case ok
        case expiresIn = "expires_in"
        case retryAfter = "retry_after"
    }
}

/// 登录页的三种方式（分段控件）。
public enum AuthMethod: String, CaseIterable, Sendable, Identifiable {
    case emailPassword, emailCode, phonePassword
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .emailPassword: "邮箱"
        case .emailCode: "验证码"
        case .phonePassword: "手机号"
        }
    }

    /// 验证码方式没有「注册」：新邮箱第一次登录即创建账号。
    public var supportsRegister: Bool { self != .emailCode }
}

/// 与后端 services/auth.py 一致的输入规则（客户端只做提示，最终以后端为准）。
public enum AuthInputRules {
    public static let passwordMin = 8
    public static let legacyPasswordMin = 6

    public static func normalizedEmail(_ raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard v.count <= 254, let at = v.firstIndex(of: "@") else { return nil }
        let local = v[..<at], domain = v[v.index(after: at)...]
        guard !local.isEmpty, local.count <= 64, domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix("."),
              !v.contains(" ") else { return nil }
        return v
    }

    /// 13800138000 → +8613800138000；+1 415 555 0123 → +14155550123；不合法返回 nil。
    public static func normalizedPhone(_ raw: String) -> String? {
        var v = raw.filter { !" -()".contains($0) }
        if v.count == 11, v.first == "1", v.allSatisfy(\.isNumber), let second = v.dropFirst().first, "3456789".contains(second) {
            v = "+86" + v
        } else if v.hasPrefix("0086") {
            v = "+" + v.dropFirst(2)
        }
        guard v.hasPrefix("+"), (9...16).contains(v.count), v.dropFirst().allSatisfy(\.isNumber),
              v.dropFirst().first != "0" else { return nil }
        return v
    }

    /// 界面显示：+8613800138000 → +86 138 0013 8000；其他国家原样。
    public static func displayPhone(_ e164: String) -> String {
        guard e164.hasPrefix("+86"), e164.count == 14 else { return e164 }
        let d = Array(e164.dropFirst(3))
        return "+86 \(String(d[0..<3])) \(String(d[3..<7])) \(String(d[7..<11]))"
    }

    public static func isValidCode(_ raw: String) -> Bool {
        let v = raw.trimmingCharacters(in: .whitespaces)
        return v.count == 6 && v.allSatisfy(\.isNumber)
    }
}
