// 长期记忆（Memory，后端 schema v4）：与 /api/memories*、/api/memory/settings 的 JSON 一一对应。
// 契约见 docs/design/MEMORY_GROWTH.md §5.5。所有枚举对未知取值解码为 .unknown（兼容后端以后新增的类型）。
import Foundation

public enum MemoryScope: String, Codable, Sendable, Hashable, CaseIterable {
    case global, bot, summary, unknown
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public enum MemoryType: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case profile, preference, fact, style, summary, routine, unknown
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
    /// M1 允许用户 / Bot 写入的类型（与后端 policy.TYPES_M1 一致）
    public static let editable: [MemoryType] = [.profile, .preference, .fact]
    public var title: String {
        switch self {
        case .profile: return "资料"
        case .preference: return "偏好"
        case .fact: return "事实"
        case .style: return "风格"
        case .summary: return "摘要"
        case .routine: return "习惯"
        case .unknown: return "其他"
        }
    }
}

public enum MemoryStatus: String, Codable, Sendable, Hashable {
    case proposed, candidate, active, rejected, expired, unknown
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
    public var isPending: Bool { self == .proposed || self == .candidate }
}

public enum MemoryAction: String, Codable, Sendable, Hashable {
    case create, update, delete, unknown
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public struct MemoryEvidence: Codable, Sendable, Hashable, Identifiable {
    public let messageID: Int
    public let date: String
    public let role: String
    public var id: Int { messageID }

    enum CodingKeys: String, CodingKey { case messageID = "message_id", date, role }
}

/// 敏感类别：health / finance 的正文在服务器加密保存，界面标注「敏感」。
public enum MemorySensitivity: String, Codable, Sendable, Hashable {
    case normal, health, finance, unknown
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
    public var title: String? {
        switch self {
        case .health: return "健康信息"
        case .finance: return "财务信息"
        case .normal, .unknown: return nil
        }
    }
}

/// 每个 Bot 的记忆授权（bots.memory_access）。默认 bot_and_global（Boss 决策：记忆默认开启）。
public enum MemoryAccess: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case none
    case bot
    case botAndGlobal = "bot_and_global"
    public var id: String { rawValue }
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .botAndGlobal
    }
    public var title: String {
        switch self {
        case .none: return "不使用"
        case .bot: return "仅本 Bot 的记忆"
        case .botAndGlobal: return "本 Bot + 共享资料"
        }
    }
}

public struct Memory: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let scope: MemoryScope
    public let botId: Int?
    public let botName: String?
    public let type: MemoryType
    public let content: String
    public let sensitivity: MemorySensitivity
    public let sensitive: Bool
    public let source: String
    public let sourceBotId: Int?
    public let sourceBotName: String?
    public let status: MemoryStatus
    public let action: MemoryAction
    public let targetId: Int?
    public let targetContent: String?
    public let useCount: Int
    public let lastUsedAt: String?
    public let confirmedAt: String?
    public let expiresAt: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let evidence: [MemoryEvidence]
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case id, scope, type, content, sensitivity, sensitive, source, status, action
        case botId = "bot_id", botName = "bot_name"
        case sourceBotId = "source_bot_id", sourceBotName = "source_bot_name"
        case targetId = "target_id", targetContent = "target_content"
        case useCount = "use_count", lastUsedAt = "last_used_at", confirmedAt = "confirmed_at"
        case expiresAt = "expires_at", createdAt = "created_at", updatedAt = "updated_at"
        case evidence, reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        scope = try c.decodeIfPresent(MemoryScope.self, forKey: .scope) ?? .unknown
        botId = try c.decodeIfPresent(Int.self, forKey: .botId)
        botName = try c.decodeIfPresent(String.self, forKey: .botName)
        type = try c.decodeIfPresent(MemoryType.self, forKey: .type) ?? .unknown
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        sensitivity = try c.decodeIfPresent(MemorySensitivity.self, forKey: .sensitivity) ?? .normal
        sensitive = try c.decodeIfPresent(Bool.self, forKey: .sensitive) ?? (sensitivity != .normal)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        sourceBotId = try c.decodeIfPresent(Int.self, forKey: .sourceBotId)
        sourceBotName = try c.decodeIfPresent(String.self, forKey: .sourceBotName)
        status = try c.decodeIfPresent(MemoryStatus.self, forKey: .status) ?? .unknown
        action = try c.decodeIfPresent(MemoryAction.self, forKey: .action) ?? .create
        targetId = try c.decodeIfPresent(Int.self, forKey: .targetId)
        targetContent = try c.decodeIfPresent(String.self, forKey: .targetContent)
        useCount = try c.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        confirmedAt = try c.decodeIfPresent(String.self, forKey: .confirmedAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        evidence = try c.decodeIfPresent([MemoryEvidence].self, forKey: .evidence) ?? []
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }

    /// 来源文案：「来自与 Vera 的对话」「你手动添加」
    public var sourceTitle: String {
        switch source {
        case "memory_page": return "你手动添加"
        case "explicit_chat":
            if let n = sourceBotName { return "来自与 \(n) 的对话" }
            return "来自对话"
        case "summary_job": return "对话摘要"
        case "feedback": return "来自你的反馈"
        case "implicit_extraction": return "从对话中发现"
        default: return "其他来源"
        }
    }

    /// 次要信息行：「偏好 · 来自与 Vera 的对话 · 10/1」
    public func detailLine(now: Date = Date(), calendar: Calendar = .current) -> String {
        var parts = [type.title]
        if let s = sensitivity.title { parts.append(s) }
        parts.append(sourceTitle)
        if let d = ListTimestamp.parse(confirmedAt ?? createdAt) {
            parts.append(ListTimestamp.label(for: d, now: now, calendar: calendar))
        }
        return parts.joined(separator: " · ")
    }
}

public enum MemorySuggestionKind: String, Codable, Sendable, Hashable {
    case routineReminder = "routine_reminder"
    case delegation
    case unknown
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public struct MemorySuggestion: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let kind: MemorySuggestionKind
    public let title: String
    public let createdAt: String?
    public let expiresAt: String?
    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(MemorySuggestionKind.self, forKey: .kind) ?? .unknown
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
    }
}

public struct MemorySuggestionsResponse: Decodable, Sendable {
    public let suggestions: [MemorySuggestion]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestions = try c.decodeIfPresent([MemorySuggestion].self, forKey: .suggestions) ?? []
    }
    enum CodingKeys: String, CodingKey { case suggestions }
}

public struct SuggestionDecisionResponse: Decodable, Sendable, Hashable {
    public let id: Int?
    public let status: String
    public let kind: MemorySuggestionKind?
    public let reminderID: Int?
    public let settingsBotID: Int?
    public let targetBotID: Int?
    enum CodingKeys: String, CodingKey {
        case id, status, kind
        case reminderID = "reminder_id"
        case settingsBotID = "settings_bot_id"
        case targetBotID = "target_bot_id"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        kind = try c.decodeIfPresent(MemorySuggestionKind.self, forKey: .kind)
        reminderID = try c.decodeIfPresent(Int.self, forKey: .reminderID)
        settingsBotID = try c.decodeIfPresent(Int.self, forKey: .settingsBotID)
        targetBotID = try c.decodeIfPresent(Int.self, forKey: .targetBotID)
    }
}

public struct QuickPromptsResponse: Decodable, Sendable, Hashable {
    public let prompts: [String]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prompts = Array((try c.decodeIfPresent([String].self, forKey: .prompts) ?? []).prefix(6))
    }
    enum CodingKeys: String, CodingKey { case prompts }
}

public struct MemoryCounts: Codable, Sendable, Hashable {
    public let active: Int
    public let proposed: Int
    public let candidate: Int
    public let global: Int
    public let byBot: [String: Int]

    enum CodingKeys: String, CodingKey {
        case active, proposed, candidate, global
        case byBot = "by_bot"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = try c.decodeIfPresent(Int.self, forKey: .active) ?? 0
        proposed = try c.decodeIfPresent(Int.self, forKey: .proposed) ?? 0
        candidate = try c.decodeIfPresent(Int.self, forKey: .candidate) ?? 0
        global = try c.decodeIfPresent(Int.self, forKey: .global) ?? 0
        byBot = try c.decodeIfPresent([String: Int].self, forKey: .byBot) ?? [:]
    }
}

public struct MemoryLimits: Codable, Sendable, Hashable {
    public let maxActive: Int
    public let maxChars: Int
    enum CodingKeys: String, CodingKey {
        case maxActive = "max_active", maxChars = "max_chars"
    }
}

public struct MemoriesResponse: Codable, Sendable {
    public let memories: [Memory]
    public let counts: MemoryCounts?
    public let limits: MemoryLimits?
}

/// GET /api/memories 的查询条件（nil = 不过滤）。
public struct MemoryQuery: Sendable, Hashable {
    public var statuses: [MemoryStatus]
    public var scope: MemoryScope?
    public var botID: Int?
    public var ids: [Int]?
    /// 只返回某个 Bot 能看到的记忆（本 Bot 记忆 + 按其 memory_access 可见的共享资料）
    public var visibleTo: Int?

    public init(statuses: [MemoryStatus] = [.active], scope: MemoryScope? = nil, botID: Int? = nil,
                ids: [Int]? = nil, visibleTo: Int? = nil) {
        self.statuses = statuses
        self.scope = scope
        self.botID = botID
        self.ids = ids
        self.visibleTo = visibleTo
    }

    public var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "status", value: statuses.map(\.rawValue).joined(separator: ","))]
        if let scope { items.append(URLQueryItem(name: "scope", value: scope.rawValue)) }
        if let botID { items.append(URLQueryItem(name: "bot_id", value: String(botID))) }
        if let ids, !ids.isEmpty { items.append(URLQueryItem(name: "ids", value: ids.map(String.init).joined(separator: ","))) }
        if let visibleTo { items.append(URLQueryItem(name: "visible_to", value: String(visibleTo))) }
        return items
    }
}

public enum MemoryFilter {
    public static func matches(_ memory: Memory, query: String, type: MemoryType?) -> Bool {
        if let type, memory.type != type { return false }
        let term=query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || memory.content.localizedCaseInsensitiveContains(term)
    }
}

public struct BotGrowth: Codable, Sendable, Hashable {
    public let botId: Int
    public let memoryCounts: [String:Int]
    public let assistedCount: Int
    public let firstConversationAt: String?
    public let recentMemories: [Memory]
    enum CodingKeys:String,CodingKey { case botId="bot_id",memoryCounts="memory_counts",assistedCount="assisted_count",firstConversationAt="first_conversation_at",recentMemories="recent_memories" }
}

public struct MonthlyMemoryReview: Codable, Sendable, Hashable {
    public let month:String
    public let reviewStatus:String
    public let assistedCount:Int
    public let assistantMessages:Int?
    public let successfulDelegations:Int?
    public let firstConversationAt:String?
    public let capabilities:[String:Int]
    public let newMemories:[Memory]
    public let candidateCount:Int
    public let suggestion:String?
    enum CodingKeys:String,CodingKey { case month,reviewStatus="review_status",assistedCount="assisted_count",assistantMessages="assistant_messages",successfulDelegations="successful_delegations",firstConversationAt="first_conversation_at",capabilities,newMemories="new_memories",candidateCount="candidate_count",suggestion }
    public init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        month=try c.decodeIfPresent(String.self,forKey:.month) ?? ""
        reviewStatus=try c.decodeIfPresent(String.self,forKey:.reviewStatus) ?? "unavailable"
        assistedCount=try c.decodeIfPresent(Int.self,forKey:.assistedCount) ?? 0
        assistantMessages=try c.decodeIfPresent(Int.self,forKey:.assistantMessages)
        successfulDelegations=try c.decodeIfPresent(Int.self,forKey:.successfulDelegations)
        firstConversationAt=try c.decodeIfPresent(String.self,forKey:.firstConversationAt)
        capabilities=try c.decodeIfPresent([String:Int].self,forKey:.capabilities) ?? [:]
        newMemories=try c.decodeIfPresent([Memory].self,forKey:.newMemories) ?? []
        candidateCount=try c.decodeIfPresent(Int.self,forKey:.candidateCount) ?? 0
        suggestion=try c.decodeIfPresent(String.self,forKey:.suggestion)
    }
}

public struct MemoryReferencesResponse:Codable,Sendable,Hashable { public let messageId:Int; public let memories:[Memory]; enum CodingKeys:String,CodingKey {case messageId="message_id",memories} }
public struct MemoryExportItem:Codable,Sendable,Hashable,Identifiable {
    public let id:Int
    public let scope:String
    public let botId:Int?
    public let type:String
    public let source:String
    public let sourceBotId:Int?
    public let sourceMessageId:Int?
    public let status:String
    public let action:String?
    public let targetId:Int?
    public let sensitivity:String
    public let confidence:Double
    public let useCount:Int
    public let lastUsedAt:String?
    public let confirmedAt:String?
    public let expiresAt:String?
    public let createdAt:String?
    public let updatedAt:String?
    public let content:String
    enum CodingKeys:String,CodingKey {case id,scope,type,source,status,sensitivity,confidence,content,botId="bot_id",sourceBotId="source_bot_id",sourceMessageId="source_message_id",action,targetId="target_id",useCount="use_count",lastUsedAt="last_used_at",confirmedAt="confirmed_at",expiresAt="expires_at",createdAt="created_at",updatedAt="updated_at"}
}
public struct MemoryExportResponse:Codable,Sendable { public let format:String; public let memories:[MemoryExportItem] }

/// POST /api/memories（记忆页手动添加，直接生效）
public struct MemoryCreate: Codable, Sendable {
    public var content: String
    public var type: MemoryType
    public var scope: MemoryScope
    public var botId: Int?

    public init(content: String, type: MemoryType, scope: MemoryScope, botId: Int? = nil) {
        self.content = content
        self.type = type
        self.scope = scope
        self.botId = botId
    }

    enum CodingKeys: String, CodingKey {
        case content, type, scope
        case botId = "bot_id"
    }
}

/// PATCH /api/memories/{id}：nil 字段不编码（不修改）。
public struct MemoryPatch: Codable, Sendable {
    public var content: String?
    public var type: MemoryType?
    public var scope: MemoryScope?
    public var botId: Int?

    public init(content: String? = nil, type: MemoryType? = nil, scope: MemoryScope? = nil, botId: Int? = nil) {
        self.content = content
        self.type = type
        self.scope = scope
        self.botId = botId
    }

    enum CodingKeys: String, CodingKey {
        case content, type, scope
        case botId = "bot_id"
    }
}

/// POST /api/memories/{id}/confirm 的结果：create / update → 生效的 Memory；delete 提议 → 被删除的记忆 id。
public enum MemoryConfirmResult: Decodable, Sendable {
    case memory(Memory)
    case deleted(Int)

    private enum Keys: String, CodingKey { case deletedId = "deleted_id" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let id = try c.decodeIfPresent(Int.self, forKey: .deletedId) {
            self = .deleted(id)
        } else {
            self = .memory(try Memory(from: decoder))
        }
    }
}

public struct MemorySettings: Codable, Sendable, Hashable {
    public let enabled: Bool
    public let serverEnabled: Bool
    public let activeCount: Int
    public let maxActive: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case serverEnabled = "server_enabled"
        case activeCount = "active_count"
        case maxActive = "max_active"
    }
}

/// DELETE /api/memories 的结果
public struct MemoryClearResponse: Codable, Sendable {
    public let ok: Bool
    public let deleted: Int
}

/// DELETE /api/bots/{id}/messages 的结果（include_memories=true 时 deletedMemories 为删除的记忆条数）
public struct ClearMessagesResponse: Codable, Sendable {
    public let ok: Bool
    public let deletedMemories: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case deletedMemories = "deleted_memories"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        deletedMemories = try c.decodeIfPresent(Int.self, forKey: .deletedMemories) ?? 0
    }
}

/// GET /api/tools 里的记忆摘要
public struct ToolsMemoryInfo: Codable, Sendable, Hashable {
    public let enabled: Bool
    public let maxActive: Int?
    public let injectMax: Int?
    enum CodingKeys: String, CodingKey {
        case enabled
        case maxActive = "max_active"
        case injectMax = "inject_max"
    }
}

// MARK: - 对话中的记忆提议（remember / forget_memory 的 tool trace）

/// 从 `ToolTrace.result` 解析出的记忆工具结果。`memoryID != nil && status == .proposed` 时渲染确认卡片。
public struct MemoryProposal: Sendable, Hashable {
    public let memoryID: Int?
    public let status: String?        // proposed / already_known / previously_declined …（工具当时的结果）
    public let action: MemoryAction
    public let content: String
    public let type: MemoryType
    public let scope: MemoryScope
    public let sensitive: Bool
    public let targetContent: String?
    public let errorCode: String?
    public let errorText: String?

    public var isCard: Bool { memoryID != nil && status == "proposed" }

    /// 不弹卡片时显示的一行说明
    public var summary: String {
        if let errorText { return errorText }
        switch status {
        case "already_known": return "已在记忆中"
        case "previously_declined": return "你之前选择过不记住这条"
        default: return ""
        }
    }
}

extension ToolTrace {
    public static let memoryToolNames: Set<String> = ["remember", "forget_memory"]
    public var isMemoryTool: Bool { Self.memoryToolNames.contains(name) }

    /// 记忆工具的结果（工具执行中 result 为 nil → nil）。
    public var memoryProposal: MemoryProposal? {
        guard isMemoryTool, let r = result else { return nil }
        let id: Int? = {
            if case .number(let n)? = r["memory_id"] { return Int(n) }
            return nil
        }()
        let action = MemoryAction(rawValue: r["action"]?.text ?? "") ?? (name == "forget_memory" ? .delete : .create)
        return MemoryProposal(
            memoryID: id,
            status: r["status"]?.text,
            action: action,
            content: r["content"]?.text ?? args?["content"]?.text ?? "",
            type: MemoryType(rawValue: r["type"]?.text ?? "") ?? .unknown,
            scope: MemoryScope(rawValue: r["scope"]?.text ?? "") ?? .unknown,
            sensitive: r["sensitive"]?.text == "true",
            targetContent: r["target_content"].flatMap { $0 == .null ? nil : $0.text },
            errorCode: r["code"]?.text,
            errorText: r["error"]?.text
        )
    }
}
