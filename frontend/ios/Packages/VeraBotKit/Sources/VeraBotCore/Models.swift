// VeraBotCore：共享数据模型（Shared models），与后端 JSON 一一对应。不依赖 UI / 网络。
import Foundation

public struct User: Codable, Sendable, Hashable {
    public let id: Int
    public let username: String
}

public struct AuthResponse: Codable, Sendable {
    public let token: String
    public let user: User
}

public struct Credentials: Codable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct LastMessage: Codable, Sendable, Hashable {
    public let content: String
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case content
        case createdAt = "created_at"
    }
}

public struct Bot: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let avatar: String
    public let color: String
    public let persona: String
    public let instructions: String
    public let createdAt: String?
    public let lastMessage: LastMessage?
    /// 多 Agent 权限（Permissions）：工具白名单 / 可委派目标 / 是否接受委派
    public let allowedTools: [String]
    public let delegateTo: [Int]
    public let acceptDelegation: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, avatar, color, persona, instructions
        case createdAt = "created_at"
        case lastMessage = "last_message"
        case allowedTools = "allowed_tools"
        case delegateTo = "delegate_to"
        case acceptDelegation = "accept_delegation"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        avatar = try c.decode(String.self, forKey: .avatar)
        color = try c.decode(String.self, forKey: .color)
        persona = try c.decodeIfPresent(String.self, forKey: .persona) ?? ""
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        lastMessage = try c.decodeIfPresent(LastMessage.self, forKey: .lastMessage)
        allowedTools = try c.decodeIfPresent([String].self, forKey: .allowedTools) ?? []
        delegateTo = try c.decodeIfPresent([Int].self, forKey: .delegateTo) ?? []
        acceptDelegation = try c.decodeIfPresent(Bool.self, forKey: .acceptDelegation) ?? false
    }
}

/// PATCH /api/bots/{id}：nil 字段不会被编码（不修改）。
public struct BotPatch: Codable, Sendable {
    public var name: String?
    public var avatar: String?
    public var color: String?
    public var persona: String?
    public var instructions: String?
    public var allowedTools: [String]?
    public var delegateTo: [Int]?
    public var acceptDelegation: Bool?

    public init(name: String? = nil, avatar: String? = nil, color: String? = nil, persona: String? = nil,
                instructions: String? = nil, allowedTools: [String]? = nil, delegateTo: [Int]? = nil,
                acceptDelegation: Bool? = nil) {
        self.name = name
        self.avatar = avatar
        self.color = color
        self.persona = persona
        self.instructions = instructions
        self.allowedTools = allowedTools
        self.delegateTo = delegateTo
        self.acceptDelegation = acceptDelegation
    }

    enum CodingKeys: String, CodingKey {
        case name, avatar, color, persona, instructions
        case allowedTools = "allowed_tools"
        case delegateTo = "delegate_to"
        case acceptDelegation = "accept_delegation"
    }
}

public struct ToolInfo: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let label: String?
    public let description: String
    public let delegation: Bool?
    public var id: String { name }
}

public struct Guardrails: Codable, Sendable, Hashable {
    public let maxDelegationDepth: Int
    public let maxDelegationsPerTurn: Int
    public let maxSharedContext: Int
    public let maxBotsPerUser: Int

    enum CodingKeys: String, CodingKey {
        case maxDelegationDepth = "max_delegation_depth"
        case maxDelegationsPerTurn = "max_delegations_per_turn"
        case maxSharedContext = "max_shared_context"
        case maxBotsPerUser = "max_bots_per_user"
    }
}

public struct ToolsResponse: Codable, Sendable {
    public let tools: [ToolInfo]
    public let guardrails: Guardrails?
}

/// 协作记录（Delegation log）
public struct DelegationRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let fromBotId: Int
    public let fromBot: String?
    public let fromAvatar: String?
    public let toBotId: Int
    public let toBot: String?
    public let toAvatar: String?
    public let question: String
    public let sharedContext: String?
    public let sharedTruncated: Int?
    public let payload: String?
    public let answer: String?
    public let status: String
    public let reason: String?
    public let depth: Int?
    public let totalTokens: Int?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, question, payload, answer, status, reason, depth
        case fromBotId = "from_bot_id", fromBot = "from_bot", fromAvatar = "from_avatar"
        case toBotId = "to_bot_id", toBot = "to_bot", toAvatar = "to_avatar"
        case sharedContext = "shared_context", sharedTruncated = "shared_truncated"
        case totalTokens = "total_tokens", createdAt = "created_at"
    }
}

public struct DelegationsResponse: Codable, Sendable {
    public let delegations: [DelegationRecord]
}

public struct BotsResponse: Codable, Sendable {
    public let bots: [Bot]
    public let limit: Int
}

public struct BotCreate: Codable, Sendable {
    public var name: String
    public var avatar: String
    public var color: String
    public var persona: String
    public var instructions: String

    public init(name: String, avatar: String, color: String, persona: String, instructions: String) {
        self.name = name
        self.avatar = avatar
        self.color = color
        self.persona = persona
        self.instructions = instructions
    }
}

public struct OKResponse: Codable, Sendable {
    public let ok: Bool
}

/// 工具调用 / 多 Agent 交接记录（tool_start 事件时 result 为 nil）。
public struct ToolTrace: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let args: JSONValue?
    public let result: JSONValue?
}

public struct ChatMessage: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let role: String
    public let content: String
    public let traces: [ToolTrace]?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role, content, traces
        case createdAt = "created_at"
    }
}

public struct MessagesResponse: Codable, Sendable {
    public let messages: [ChatMessage]
}

public struct Reminder: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let content: String
    public let dueAt: String?
    public let done: Int
    public let botName: String?

    enum CodingKeys: String, CodingKey {
        case id, content, done
        case dueAt = "due_at"
        case botName = "bot_name"
    }
}

public struct RemindersResponse: Codable, Sendable {
    public let reminders: [Reminder]
}

public struct UsageStats: Codable, Sendable, Hashable {
    public let requests: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case requests
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct BotUsage: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let avatar: String
    public let color: String
    public let requests: Int
    public let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case id, name, avatar, color, requests
        case totalTokens = "total_tokens"
    }
}

public struct DailyUsage: Codable, Sendable, Hashable, Identifiable {
    public let date: String
    public let tokens: Int
    public var id: String { date }
}

public struct TranscribeStats: Codable, Sendable, Hashable {
    public let requests: Int
    public let seconds: Double
    public let chars: Int
}

public struct TranscribeQuota: Codable, Sendable, Hashable {
    public let today: TranscribeStats
    public let total: TranscribeStats
}

public struct Quota: Codable, Sendable {
    public let model: String
    public let dailyTokenQuota: Int
    public let today: UsageStats
    public let total: UsageStats
    public let perBot: [BotUsage]
    public let daily: [DailyUsage]
    public let delegations: Int
    public let transcribe: TranscribeQuota?   // 服务端语音转写（Web 端使用；iOS 端走系统 Speech 框架，不计入）

    enum CodingKeys: String, CodingKey {
        case model, today, total, daily, delegations, transcribe
        case dailyTokenQuota = "daily_token_quota"
        case perBot = "per_bot"
    }
}

/// 任意 JSON 值（用于异构的工具参数 / 结果）。
public enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var text: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        case .array(let a): return a.map(\.text).joined(separator: ", ")
        case .object(let o): return o.keys.sorted().map { "\($0): \(o[$0]?.text ?? "")" }.joined(separator: "; ")
        }
    }

    public var arrayValue: [JSONValue] {
        if case .array(let a) = self { return a }
        return []
    }
}
