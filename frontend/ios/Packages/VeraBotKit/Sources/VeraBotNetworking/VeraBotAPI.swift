import Foundation
import VeraBotCore

/// VeraBot 后端 API 抽象（Service protocol）。App 只依赖此协议，便于替换实现（Mock / 预览 / 其他传输层）。
public protocol VeraBotAPI: TetrisSessionAPI, DriftBottleAPI {
    func submitChatInput(botID: Int, input: ChatInputRequest) async throws -> ChatInputReceipt
    func chatInputReceipt(botID: Int, requestID: String) async throws -> ChatInputReceipt
    func chatExecution(botID: Int) async throws -> ChatExecutionSnapshot
    func stopChatTask(botID: Int, taskID: Int, version: Int, requestID: String) async throws -> ChatTaskControl
    func answerChatTask(botID: Int, taskID: Int, version: Int, waitID: String, message: String, requestID: String) async throws -> ChatTaskControl
    func conversationActivity() async throws -> ConversationActivitySnapshot
    func readConversation(kind: String, id: Int, generation: Int, messages: [MessagePublication]) async throws -> ConversationReadResponse
    func conversationEvents(afterID: Int) -> AsyncThrowingStream<DurableEvent, Error>
    func chatEvents(botID: Int, afterID: Int) -> AsyncThrowingStream<DurableEvent, Error>

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
    func tetrisCompanion(botID: Int, request: TetrisCompanionRequest) async throws -> TetrisCompanionReply
    func bots() async throws -> BotsResponse
    func createBot(_ b: BotCreate) async throws -> Bot
    func deleteBot(_ id: Int) async throws -> OKResponse
    func updateBot(_ id: Int, _ patch: BotPatch) async throws -> Bot
    /// 懒生成开场词模板（存量 Bot）；已有则原样返回。
    func ensureOpeningTemplates(botID: Int) async throws -> Bot
    func tools() async throws -> ToolsResponse
    func mcpCatalog() async throws -> MCPCatalogResponse
    func mcpServers() async throws -> MCPServersResponse
    func addMCPServer(catalogID: String) async throws -> MCPServer
    func updateMCPServer(id: Int, enabled: Bool) async throws -> MCPServer
    func setMCPConsent(id: Int, granted: Bool) async throws -> MCPServer
    func deleteMCPServer(id: Int) async throws -> OKResponse
    func syncMCPServer(id: Int) async throws -> MCPSyncResult
    func startMCPOAuth(serverID: Int) async throws -> MCPOAuthStart
    func completeMCPOAuth(serverID: Int, callback: MCPOAuthCallback) async throws -> MCPOAuthResult
    func cancelMCPOAuth(serverID: Int, state: String) async throws
    func disconnectMCPOAuth(serverID: Int) async throws
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
    /// 需授权连接器（v13）：上传令牌（后端校验后加密保存，响应不含令牌）/ 断开 / 接受工具更新
    func setPluginCredential(id: String, token: String) async throws -> Plugin
    func deletePluginCredential(id: String) async throws -> Plugin
    func acceptPluginToolChanges(id: String) async throws -> PluginAcceptChangesResult
    func delegations(botID: Int) async throws -> DelegationsResponse
    func messages(botID: Int) async throws -> MessagesResponse
    func syncMessages(botID: Int, beforeID: Int?, expectedRevision: Int64?) async throws -> MessageSyncResponse
    /// includeMemories：同时删除该 Bot 的「本 Bot 记忆」与对话摘要（默认 false，记忆保留）
    func clearMessages(botID: Int, includeMemories: Bool) async throws -> ClearMessagesResponse
    /// 删除单条消息（物理删除，只删这一条；已提取的记忆保留）。他人 / 不存在的消息 → 404
    func deleteMessage(botID: Int, messageID: Int) async throws -> OKResponse
    /// 给本人的 assistant 消息打 👍（rating 1）或 👎（rating -1，必须带 reason）。同一条可改。
    func setMessageFeedback(messageID: Int, rating: Int, reason: String?) async throws -> MessageFeedbackResponse
    /// 撤销对这条消息的反馈
    func deleteMessageFeedback(messageID: Int) async throws -> OKResponse
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
    func botGrowth(botID: Int) async throws -> BotGrowth
    func monthlyMemoryReview(month: String) async throws -> MonthlyMemoryReview
    func memoryReferences(messageID: Int) async throws -> MemoryReferencesResponse
    func memoryExport() async throws -> MemoryExportResponse
    func memorySuggestions(botID: Int) async throws -> MemorySuggestionsResponse
    func decideMemorySuggestion(id: Int, accept: Bool) async throws -> SuggestionDecisionResponse
    func quickPrompts(botID: Int) async throws -> QuickPromptsResponse
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
    // 统一事项（Items，提醒 / 待办 / Bot 任务共用）
    func items(view: String?, botID: Int?, cursor: String?, limit: Int) async throws -> ItemsResponse
    func item(id: Int) async throws -> Item
    func createItem(_ body: ItemWrite, idempotencyKey: String?) async throws -> Item
    func updateItem(id: Int, _ body: ItemWrite, idempotencyKey: String?) async throws -> Item
    func completeItem(_ id: Int, idempotencyKey: String?) async throws -> Item
    func reopenItem(_ id: Int, idempotencyKey: String?) async throws -> Item
    func snoozeItem(_ id: Int, minutes: Int?, until: String?, idempotencyKey: String?) async throws -> Item
    func skipItem(_ id: Int, idempotencyKey: String?) async throws -> Item
    func replaceChecklist(id: Int, expectedVersion: Int, items: [ChecklistWrite],
                          idempotencyKey: String?) async throws -> Item
    func toggleChecklist(id: Int, checklistID: Int, done: Bool?) async throws -> Item
    func itemTaskAction(id: Int, action: String, message: String?, idempotencyKey: String?) async throws -> Item
    func deleteItem(_ id: Int, scope: String, stopTask: Bool, idempotencyKey: String?) async throws -> Reminder
    /// Bot 托管任务详情（事项详情页跳转用）
    func ownedTask(_ id: Int) async throws -> OwnedTask
    func notifications(unread: Bool, category: String?) async throws -> NotificationsResponse
    func localNotificationState(ids: [Int]) async throws -> [InboxNotification]
    func notificationEvents(after: Int?, through: Int?) async throws -> NotificationEventPage
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
    // 图片附件（v12）：先上传拿 id，再随消息发送；原图 / 缩略图走鉴权下载（no-store）
    func chatStream(botID: Int, message: String, attachmentIDs: [String]) -> AsyncThrowingStream<ChatEvent, Error>
    func uploadAttachment(data: Data, mime: String, botID: Int?, filename: String?) async throws -> Attachment
    func attachmentContent(id: String) async throws -> Data
    func attachmentThumb(id: String) async throws -> Data
    func deleteAttachment(id: String) async throws -> OKResponse
    // MCP M3：待确认操作
    func pendingActions(status: String?, botID: Int?) async throws -> PendingActionsResponse
    func pendingAction(id: Int) async throws -> PendingAction
    func confirmPendingAction(id: Int) async throws -> PendingAction
    func cancelPendingAction(id: Int) async throws -> PendingAction
    func toolCalls(botID: Int) async throws -> ToolCallsResponse
}

/// 创建 / 修改提醒。未设置的字段不发送；`clearDue` / `clearRrule` / `clearAssignee` 显式写成 null。
public struct ReminderWrite: Encodable, Sendable {
    public var title: String?
    public var note: String?
    public var clearNote: Bool
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
                expectedVersion: Int? = nil, clearNote: Bool = false) {
        self.title = title
        self.note = note
        self.clearNote = clearNote
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
        if clearNote { try c.encodeNil(forKey: .note) } else { try c.encodeIfPresent(note, forKey: .note) }
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

// Older test clients compile safely; unsupported durable chat never falls back to request-bound generation.
public extension VeraBotAPI {
    func submitChatInput(botID: Int, input: ChatInputRequest) async throws -> ChatInputReceipt { throw APIError(status: 501, message: "后端尚未支持持续对话") }
    func chatInputReceipt(botID: Int, requestID: String) async throws -> ChatInputReceipt { throw APIError(status: 501, message: "后端尚未支持持续对话") }
    func chatExecution(botID: Int) async throws -> ChatExecutionSnapshot { throw APIError(status: 501, message: "后端尚未支持持续对话") }
    func stopChatTask(botID: Int, taskID: Int, version: Int, requestID: String) async throws -> ChatTaskControl { throw APIError(status: 501, message: "后端尚未支持持续对话") }
    func answerChatTask(botID: Int, taskID: Int, version: Int, waitID: String, message: String, requestID: String) async throws -> ChatTaskControl { throw APIError(status: 501, message: "后端尚未支持持续对话") }
    func conversationActivity() async throws -> ConversationActivitySnapshot { throw APIError(status: 501, message: "后端尚未支持会话同步") }
    func readConversation(kind: String, id: Int, generation: Int, messages: [MessagePublication]) async throws -> ConversationReadResponse { throw APIError(status: 501, message: "后端尚未支持阅读同步") }
    func conversationEvents(afterID: Int) -> AsyncThrowingStream<DurableEvent, Error> { AsyncThrowingStream { $0.finish(throwing: APIError(status: 501, message: "后端尚未支持会话同步")) } }
    func chatEvents(botID: Int, afterID: Int) -> AsyncThrowingStream<DurableEvent, Error> { AsyncThrowingStream { $0.finish(throwing: APIError(status: 501, message: "后端尚未支持持续对话")) } }
    func notificationEvents(after: Int?, through: Int?) async throws -> NotificationEventPage {
        throw APIError(status: 501, message: "通知同步暂不可用")
    }
    func ensureOpeningTemplates(botID: Int) async throws -> Bot {
        throw APIError(status: 501, message: "开场词模板接口暂不可用")
    }
    // 事项接口：协议要求无默认参数。带默认值的同名同参便利重载会静态阴影 APIClient
    //（`any VeraBotAPI` 上 `items()` 等永远落到抛 501 的扩展）。这里用「参数更少」的
    // 重载转发到完整协议要求，避免递归并让见证表走到真实实现。
    func items(view: String? = nil, botID: Int? = nil, cursor: String? = nil) async throws -> ItemsResponse {
        try await items(view: view, botID: botID, cursor: cursor, limit: 200)
    }
    func createItem(_ body: ItemWrite) async throws -> Item {
        try await createItem(body, idempotencyKey: nil)
    }
    func updateItem(id: Int, _ body: ItemWrite) async throws -> Item {
        try await updateItem(id: id, body, idempotencyKey: nil)
    }
    func completeItem(_ id: Int) async throws -> Item {
        try await completeItem(id, idempotencyKey: nil)
    }
    func reopenItem(_ id: Int) async throws -> Item {
        try await reopenItem(id, idempotencyKey: nil)
    }
    func snoozeItem(_ id: Int, minutes: Int? = nil, until: String? = nil) async throws -> Item {
        try await snoozeItem(id, minutes: minutes, until: until, idempotencyKey: nil)
    }
    func skipItem(_ id: Int) async throws -> Item {
        try await skipItem(id, idempotencyKey: nil)
    }
    func replaceChecklist(id: Int, expectedVersion: Int, items: [ChecklistWrite]) async throws -> Item {
        try await replaceChecklist(id: id, expectedVersion: expectedVersion, items: items, idempotencyKey: nil)
    }
    func toggleChecklist(id: Int, checklistID: Int) async throws -> Item {
        try await toggleChecklist(id: id, checklistID: checklistID, done: nil)
    }
    func itemTaskAction(id: Int, action: String, message: String? = nil) async throws -> Item {
        try await itemTaskAction(id: id, action: action, message: message, idempotencyKey: nil)
    }
    func deleteItem(_ id: Int, scope: String = "series", stopTask: Bool) async throws -> Reminder {
        try await deleteItem(id, scope: scope, stopTask: stopTask, idempotencyKey: nil)
    }
    func item(id: Int) async throws -> Item {
        throw APIError(status: 501, message: "事项接口暂不可用")
    }
    func ownedTask(_ id: Int) async throws -> OwnedTask {
        throw APIError(status: 501, message: "任务接口暂不可用")
    }
}
