import Foundation
import VeraBotCore

/// VeraBot 后端 API 抽象（Service protocol）。App 只依赖此协议，便于替换实现（Mock / 预览 / 其他传输层）。
public protocol VeraBotAPI: Sendable {
    func login(_ c: Credentials) async throws -> AuthResponse
    func register(_ c: Credentials) async throws -> AuthResponse
    /// v9 账号：identifier = 邮箱 / 手机号 / 用户名
    func login(_ r: LoginRequest) async throws -> AuthResponse
    func register(_ r: RegisterRequest) async throws -> AuthResponse
    func sendEmailCode(email: String) async throws -> CodeSentResponse
    func loginWithEmailCode(email: String, code: String) async throws -> AuthResponse
    func sendVerificationEmail() async throws -> CodeSentResponse
    func verifyEmail(code: String) async throws -> User
    func refresh(refreshToken: String) async throws -> AuthResponse
    func logout(refreshToken: String) async throws -> OKResponse
    func me() async throws -> User
    func updateNickname(_ nickname: String) async throws -> User
    func uploadMyAvatar(jpeg: Data) async throws -> User
    func myAvatarData() async throws -> Data
    func deleteMyAvatar() async throws -> User
    func uploadBotAvatar(botID: Int, jpeg: Data) async throws -> Bot
    func botAvatarData(botID: Int) async throws -> Data
    func deleteBotAvatar(botID: Int) async throws -> Bot
    func bots() async throws -> BotsResponse
    func createBot(_ b: BotCreate) async throws -> Bot
    func deleteBot(_ id: Int) async throws -> OKResponse
    func updateBot(_ id: Int, _ patch: BotPatch) async throws -> Bot
    func tools() async throws -> ToolsResponse
    func mcpCatalog() async throws -> MCPCatalogResponse
    func mcpServers() async throws -> MCPServersResponse
    func addMCPServer(catalogID: String) async throws -> MCPServer
    func updateMCPServer(id: Int, enabled: Bool) async throws -> MCPServer
    func setMCPConsent(id: Int, granted: Bool) async throws -> MCPServer
    func deleteMCPServer(id: Int) async throws -> OKResponse
    func syncMCPServer(id: Int) async throws -> MCPSyncResult
    func mcpTools(serverID: Int) async throws -> MCPToolsResponse
    func pluginCatalog() async throws -> PluginCatalogResponse
    func plugins() async throws -> PluginsResponse
    func plugin(id: String) async throws -> Plugin
    func installPlugin(id: String) async throws -> Plugin
    func uninstallPlugin(id: String) async throws -> PluginUninstallResult
    func updatePlugin(id: String, enabled: Bool) async throws -> Plugin
    func setPluginConsent(id: String, granted: Bool) async throws -> Plugin
    func pluginTools(id: String) async throws -> PluginToolsResponse
    func syncPlugin(id: String) async throws -> PluginSyncResult
    func delegations(botID: Int) async throws -> DelegationsResponse
    func messages(botID: Int) async throws -> MessagesResponse
    /// includeMemories：同时删除该 Bot 的「本 Bot 记忆」与对话摘要（默认 false，记忆保留）
    func clearMessages(botID: Int, includeMemories: Bool) async throws -> ClearMessagesResponse
    /// 删除单条消息（物理删除，只删这一条；已提取的记忆保留）。他人 / 不存在的消息 → 404
    func deleteMessage(botID: Int, messageID: Int) async throws -> OKResponse
    // 长期记忆（Memory，后端 schema v4）
    func memories(_ query: MemoryQuery) async throws -> MemoriesResponse
    func memory(id: Int) async throws -> Memory
    func createMemory(_ m: MemoryCreate) async throws -> Memory
    func updateMemory(id: Int, _ patch: MemoryPatch) async throws -> Memory
    func deleteMemory(id: Int) async throws -> OKResponse
    /// scope nil = 全部；.bot 需传 botID
    func clearMemories(scope: MemoryScope?, botID: Int?) async throws -> MemoryClearResponse
    func confirmMemory(id: Int, content: String?) async throws -> MemoryConfirmResult
    func rejectMemory(id: Int) async throws -> OKResponse
    func memorySettings() async throws -> MemorySettings
    func updateMemorySettings(enabled: Bool) async throws -> MemorySettings
    func reminders() async throws -> RemindersResponse
    func reminder(id: Int) async throws -> Reminder
    func createReminder(_ body: ReminderWrite) async throws -> Reminder
    func updateReminder(id: Int, _ body: ReminderWrite) async throws -> Reminder
    func completeReminder(_ id: Int, idempotencyKey: String?) async throws -> Reminder
    func snoozeReminder(_ id: Int, minutes: Int?, until: String?, idempotencyKey: String?) async throws -> Reminder
    func reopenReminder(_ id: Int) async throws -> Reminder
    func skipReminder(_ id: Int) async throws -> Reminder
    func restoreReminder(_ id: Int) async throws -> Reminder
    func deleteReminder(_ id: Int, scope: String) async throws -> Reminder
    func notifications(unread: Bool, category: String?) async throws -> NotificationsResponse
    func notificationSummary() async throws -> NotificationSummary
    func markNotificationRead(_ id: Int) async throws -> InboxNotification
    func markNotificationUnread(_ id: Int) async throws -> InboxNotification
    func markAllNotificationsRead() async throws -> OKResponse
    func deleteNotification(_ id: Int) async throws -> OKResponse
    func reportNotification(id: Int, event: String, channel: String, deviceId: String?) async throws -> OKResponse
    func notificationSettings() async throws -> NotificationSettings
    func updateNotificationSettings(_ body: NotificationSettings) async throws -> NotificationSettings
    func registerDevice(_ body: DeviceRegistration) async throws -> DeviceRegistration
    func deleteDevice(_ deviceId: String) async throws -> OKResponse
    func quota() async throws -> Quota
    func health() async throws -> HealthStatus
    func chatStream(botID: Int, message: String) -> AsyncThrowingStream<ChatEvent, Error>
}

/// 创建 / 修改提醒。未设置的字段不发送；`clearDue` / `clearRrule` / `clearAssignee` 显式写成 null。
public struct ReminderWrite: Encodable, Sendable {
    public var title: String?
    public var note: String?
    public var dueAt: String?
    public var clearDue: Bool
    public var timeZone: String?
    public var allDay: Bool?
    public var rrule: String?
    public var clearRrule: Bool
    public var priority: Int?
    public var assigneeBotId: Int?
    public var clearAssignee: Bool
    public var notify: Bool?
    public var expectedVersion: Int?

    enum CodingKeys: String, CodingKey {
        case title, note, priority, notify, rrule
        case dueAt = "due_at"
        case timeZone = "timezone"
        case allDay = "all_day"
        case assigneeBotId = "assignee_bot_id"
        case expectedVersion = "expected_version"
    }

    public init(title: String? = nil, note: String? = nil, dueAt: String? = nil, clearDue: Bool = false,
                timeZone: String? = nil, allDay: Bool? = nil, rrule: String? = nil, clearRrule: Bool = false,
                priority: Int? = nil, assigneeBotId: Int? = nil, clearAssignee: Bool = false, notify: Bool? = nil,
                expectedVersion: Int? = nil) {
        self.title = title
        self.note = note
        self.dueAt = dueAt
        self.clearDue = clearDue
        self.timeZone = timeZone
        self.allDay = allDay
        self.rrule = rrule
        self.clearRrule = clearRrule
        self.priority = priority
        self.assigneeBotId = assigneeBotId
        self.clearAssignee = clearAssignee
        self.notify = notify
        self.expectedVersion = expectedVersion
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(note, forKey: .note)
        if clearDue { try c.encodeNil(forKey: .dueAt) } else { try c.encodeIfPresent(dueAt, forKey: .dueAt) }
        try c.encodeIfPresent(timeZone, forKey: .timeZone)
        try c.encodeIfPresent(allDay, forKey: .allDay)
        if clearRrule { try c.encodeNil(forKey: .rrule) } else { try c.encodeIfPresent(rrule, forKey: .rrule) }
        try c.encodeIfPresent(priority, forKey: .priority)
        if clearAssignee {
            try c.encodeNil(forKey: .assigneeBotId)
        } else {
            try c.encodeIfPresent(assigneeBotId, forKey: .assigneeBotId)
        }
        try c.encodeIfPresent(notify, forKey: .notify)
        try c.encodeIfPresent(expectedVersion, forKey: .expectedVersion)
    }
}

struct SnoozeBody: Encodable {
    var minutes: Int?
    var until: String?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(minutes, forKey: .minutes)
        try c.encodeIfPresent(until, forKey: .until)
    }
    enum CodingKeys: String, CodingKey { case minutes, until }
}

struct DeliveryEventBody: Encodable {
    var event: String
    var channel: String
    var deviceId: String?
    enum CodingKeys: String, CodingKey {
        case event, channel
        case deviceId = "device_id"
    }
}
