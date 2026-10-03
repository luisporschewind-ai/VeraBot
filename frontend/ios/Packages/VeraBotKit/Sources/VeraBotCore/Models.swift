// VeraBotCore：共享数据模型（Shared models），与后端 JSON 一一对应。不依赖 UI / 网络。
import Foundation

public struct User: Codable, Sendable, Hashable {
    public let id: Int
    public let username: String
    /// 用户设置的昵称。nil 表示未设置，界面用 displayName（回退用户名）。
    public let nickname: String?
    public let displayName: String
    public let hasAvatar: Bool
    public let avatarUpdatedAt: String?

    public init(id: Int, username: String, nickname: String? = nil, displayName: String? = nil,
                hasAvatar: Bool = false, avatarUpdatedAt: String? = nil) {
        self.id = id
        self.username = username
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nick = (trimmed?.isEmpty == false) ? trimmed : nil
        self.nickname = nick
        let shown = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let shown, !shown.isEmpty {
            self.displayName = shown
        } else {
            self.displayName = nick ?? username
        }
        self.hasAvatar = hasAvatar
        self.avatarUpdatedAt = avatarUpdatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, username, nickname
        case displayName = "display_name"
        case hasAvatar = "has_avatar"
        case avatarUpdatedAt = "avatar_updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(Int.self, forKey: .id),
            username: try c.decode(String.self, forKey: .username),
            nickname: try c.decodeIfPresent(String.self, forKey: .nickname),
            displayName: try c.decodeIfPresent(String.self, forKey: .displayName),
            hasAvatar: try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false,
            avatarUpdatedAt: try c.decodeIfPresent(String.self, forKey: .avatarUpdatedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        try c.encodeIfPresent(nickname, forKey: .nickname)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(hasAvatar, forKey: .hasAvatar)
        try c.encodeIfPresent(avatarUpdatedAt, forKey: .avatarUpdatedAt)
    }
}

/// 昵称规则，与后端 `clean_nickname` 一致：去空白、1…32 个字、不含控制字符。
public enum NicknameRules {
    public static let maxCount = 32

    public static func cleaned(_ raw: String) -> String? {
        if raw.count > 64 { return nil }
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, v.count <= maxCount else { return nil }
        if v.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) { return nil }
        return v
    }
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
    /// 是否设置了照片头像（表情符号仍在 avatar）。
    public let hasAvatar: Bool
    public let avatarUpdatedAt: String?
    /// 记忆授权（schema v4）。旧后端没有该字段时按默认 bot_and_global。
    public let memoryAccess: MemoryAccess
    /// 该 Bot 的生效「本 Bot 记忆」条数（不含共享资料）；旧后端为 nil。
    public let memoryCount: Int?
    /// 标签。旧后端没有该字段时为空列表。
    public let tags: [String]
    /// 置顶时间（UTC ISO 8601）；旧后端缺失或 null 时未置顶。
    public private(set) var pinnedAt: String?
    public var isPinned: Bool { pinnedAt != nil }

    public func replacingPinnedAt(_ value: String?) -> Bot {
        var copy = self
        copy.pinnedAt = value
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case id, name, avatar, color, persona, instructions
        case createdAt = "created_at"
        case lastMessage = "last_message"
        case allowedTools = "allowed_tools"
        case delegateTo = "delegate_to"
        case acceptDelegation = "accept_delegation"
        case hasAvatar = "has_avatar"
        case avatarUpdatedAt = "avatar_updated_at"
        case memoryAccess = "memory_access"
        case memoryCount = "memory_count"
        case tags
        case pinnedAt = "pinned_at"
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
        hasAvatar = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        avatarUpdatedAt = try c.decodeIfPresent(String.self, forKey: .avatarUpdatedAt)
        memoryAccess = try c.decodeIfPresent(MemoryAccess.self, forKey: .memoryAccess) ?? .botAndGlobal
        memoryCount = try c.decodeIfPresent(Int.self, forKey: .memoryCount)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        pinnedAt = try c.decodeIfPresent(String.self, forKey: .pinnedAt)
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
    public var memoryAccess: MemoryAccess?
    /// nil = 不修改；空数组 = 清空。
    public var tags: [String]?
    public var pinned: Bool?

    public init(name: String? = nil, avatar: String? = nil, color: String? = nil, persona: String? = nil,
                instructions: String? = nil, allowedTools: [String]? = nil, delegateTo: [Int]? = nil,
                acceptDelegation: Bool? = nil, memoryAccess: MemoryAccess? = nil, tags: [String]? = nil,
                pinned: Bool? = nil) {
        self.name = name
        self.avatar = avatar
        self.color = color
        self.persona = persona
        self.instructions = instructions
        self.allowedTools = allowedTools
        self.delegateTo = delegateTo
        self.acceptDelegation = acceptDelegation
        self.memoryAccess = memoryAccess
        self.tags = tags
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey {
        case name, avatar, color, persona, instructions
        case allowedTools = "allowed_tools"
        case delegateTo = "delegate_to"
        case acceptDelegation = "accept_delegation"
        case memoryAccess = "memory_access"
        case tags
        case pinned
    }
}

/// 与后端 GET /api/bots 一致：置顶按时间倒序（并列按 id 升序），其余按 id 升序。
public enum BotOrdering {
    public static func sorted(_ bots: [Bot]) -> [Bot] {
        bots.sorted { lhs, rhs in
            switch (lhs.pinnedAt, rhs.pinnedAt) {
            case let (l?, r?):
                return l == r ? lhs.id < rhs.id : l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.id < rhs.id
            }
        }
    }

    /// 与后端 db.now_iso() 同格式（UTC、精确到秒、+00:00），便于乐观置顶后与服务端值按字符串排序一致。
    public static func pinTimestamp(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date).replacingOccurrences(of: "Z", with: "+00:00")
    }

    /// 乐观置顶 / 取消置顶：先在本地改 pinnedAt 并重排，再与服务端同步。
    /// 新置顶时间取 now；若本机时钟不晚于已有最新置顶，则取其 +1 秒，保证即使本机时钟偏慢也排在最前（与服务端「最新置顶在前」一致）。
    public static func togglingPin(_ bots: [Bot], id: Int, now: Date = Date()) -> [Bot] {
        guard let target = bots.first(where: { $0.id == id }) else { return bots }
        let value: String?
        if target.isPinned {
            value = nil
        } else {
            let stamp = pinTimestamp(now)
            if let newest = bots.compactMap(\.pinnedAt).max(), newest >= stamp,
               let date = ISO8601DateFormatter().date(from: newest) {
                value = pinTimestamp(date.addingTimeInterval(1))
            } else {
                value = stamp
            }
        }
        return sorted(replacingPinnedAt(bots, id: id, value: value))
    }

    /// 用服务端返回值校正某个 Bot 的 pinnedAt 并重排。
    public static func replacingPinnedAt(_ bots: [Bot], id: Int, value: String?) -> [Bot] {
        sorted(bots.map { $0.id == id ? $0.replacingPinnedAt(value) : $0 })
    }
}

public struct ToolInfo: Codable, Sendable, Hashable, Identifiable {
    public let name: String
    public let label: String?
    public let description: String
    public let delegation: Bool?
    /// builtin / mcp。旧后端没有该字段时当作内置工具。
    public let source: String?
    public let server: String?
    public let serverId: Int?
    public let risk: String?
    public let requiresConfirmation: Bool?
    public let delegable: Bool?
    public let status: String?
    public var id: String { name }
    public var isMCP: Bool { source == "mcp" }

    enum CodingKeys: String, CodingKey {
        case name
        case label
        case description
        case delegation
        case source
        case server
        case serverId = "server_id"
        case risk
        case requiresConfirmation = "requires_confirmation"
        case delegable
        case status
    }
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
    /// 记忆摘要（v4 起；记忆工具不在 tools 列表里，由 Bot 的 memory_access 控制）
    public let memory: ToolsMemoryInfo?
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
    public var tags: [String]

    public init(name: String, avatar: String, color: String, persona: String, instructions: String,
                tags: [String] = []) {
        self.name = name
        self.avatar = avatar
        self.color = color
        self.persona = persona
        self.instructions = instructions
        self.tags = tags
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
    public let hasAvatar: Bool
    public let avatarUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, avatar, color, requests
        case totalTokens = "total_tokens"
        case hasAvatar = "has_avatar"
        case avatarUpdatedAt = "avatar_updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        avatar = try c.decode(String.self, forKey: .avatar)
        color = try c.decode(String.self, forKey: .color)
        requests = try c.decode(Int.self, forKey: .requests)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens)
        hasAvatar = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        avatarUpdatedAt = try c.decodeIfPresent(String.self, forKey: .avatarUpdatedAt)
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

extension Quota {
    /// 今日 Token 已用百分比 = `today.total_tokens` / `daily_token_quota` × 100，四舍五入取整。
    /// 与后端拦截用的是同一对数值 (`db.token_budget`：今日已用 vs 个人预算或 `VERABOT_DAILY_TOKEN_QUOTA`)。
    /// 额度 ≤ 0 (无有效额度) 时返回 nil，界面不显示数字。超额时如实返回 > 100 的值，不截断。
    public var usedPercent: Int? {
        guard dailyTokenQuota > 0 else { return nil }
        return Int((Double(max(today.totalTokens, 0)) / Double(dailyTokenQuota) * 100).rounded())
    }

    /// 设置 › 用量 行右侧的文案，例如「已用 37%」；无有效额度时为 nil。
    public var usedPercentText: String? {
        usedPercent.map { "已用 \($0)%" }
    }
}

/// GET /api/health：后端健康检查（设置 › 调试页使用）。
public struct HealthStatus: Codable, Sendable, Hashable {
    public let ok: Bool
    public let model: String?
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
