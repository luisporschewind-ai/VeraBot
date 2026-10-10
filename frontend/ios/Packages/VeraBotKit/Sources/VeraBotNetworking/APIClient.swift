// VeraBotNetworking：REST + SSE 客户端。
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // Linux 上 URLSession 在这个模块；Apple 平台仍由 Foundation 提供
#endif
import VeraBotCore

public struct APIError: LocalizedError, Sendable {
    public let status: Int
    public let message: String
    /// 后端 {"detail": {"message", "code"}} 里的机器可读原因（如 sensitive_credential / memory_limit）
    public let code: String?

    public init(status: Int, message: String, code: String? = nil) {
        self.status = status
        self.message = message
        self.code = code
    }
    public var errorDescription: String? { message }
}

/// SSE 事件（与后端 /api/bots/{id}/chat 对应）。
public enum ChatEvent: Sendable {
    case delta(String)
    case toolStart(ToolTrace)
    case toolResult(ToolTrace)
    /// 召回记忆 / 委派内部进度（新后端；旧后端不发）
    case status(ChatStatus)
    /// MCP M3：待确认操作（旧客户端忽略）
    case confirmationRequired(ConfirmationRequired)
    case error(String)
    case done(ChatDone)
    /// 对话进行中产生的通知。旧客户端忽略；状态机不因此改变。
    case notification(ChatNotification)
}

extension ChatEvent {
    /// 对应的执行状态机输入（见 VeraBotCore `ExecutionStateMachine`）。
    public var executionEvent: ExecutionEvent {
        switch self {
        case .delta(let t): .delta(t)
        case .toolStart(let trace): .toolStart(trace)
        case .toolResult(let trace): .toolResult(trace)
        case .status(let s): .status(s)
        case .confirmationRequired: .notification   // 不改变流程；等用户点确认
        case .error(let msg): .error(msg)
        case .done: .done
        case .notification: .notification
        }
    }
}

/// SSE done 事件：本条回复的消息 id、本轮用户消息的 id（`user_message_id`，旧后端不发 → nil），以及本轮注入了哪些记忆（v4 起，旧后端为空）。
public struct ChatDone: Decodable, Sendable, Hashable {
    public let messageID: Int?
    public let userMessageID: Int?
    public let memoryIDs: [Int]

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case userMessageID = "user_message_id"
        case memoryIDs = "memory_ids"
    }

    public init(messageID: Int? = nil, userMessageID: Int? = nil, memoryIDs: [Int] = []) {
        self.messageID = messageID
        self.userMessageID = userMessageID
        self.memoryIDs = memoryIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageID = try c.decodeIfPresent(Int.self, forKey: .messageID)
        userMessageID = try c.decodeIfPresent(Int.self, forKey: .userMessageID)
        memoryIDs = try c.decodeIfPresent([Int].self, forKey: .memoryIDs) ?? []
    }
}

private struct DeltaPayload: Decodable { let text: String }
private struct ErrorPayload: Decodable { let message: String }
private struct ErrorBody: Decodable { let detail: JSONValue? }

/// VeraBotAPI 的 HTTP 实现：无状态值类型、Sendable，可安全跨并发域传递。
public struct APIClient: VeraBotAPI {
    public let baseURL: URL
    /// 固定令牌（测试 / 旧用法）；有 session 时以 session 为准。
    public let fixedToken: String?
    /// 共享令牌容器：401 时用刷新令牌换新的访问令牌并重试一次（见 AuthSession）。
    public let session: AuthSession?
    /// 发请求用的 URLSession：默认 `APITransport.session`（无 URLCache，不把账号数据写进磁盘缓存）。
    public let urlSession: URLSession

    public init(baseURL: URL, token: String?, urlSession: URLSession = APITransport.session) {
        self.baseURL = baseURL
        self.fixedToken = token
        self.session = nil
        self.urlSession = urlSession
    }

    public init(baseURL: URL, session: AuthSession, urlSession: URLSession = APITransport.session) {
        self.baseURL = baseURL
        self.fixedToken = nil
        self.session = session
        self.urlSession = urlSession
    }

    public var token: String? { session?.accessToken ?? fixedToken }

    // MARK: - Auth（v9：邮箱 / 手机号 / 验证码；旧的用户名 Credentials 仍可用）
    public func login(_ c: Credentials) async throws -> AuthResponse {
        try await call("/api/auth/login", method: "POST", body: try encode(c))
    }

    public func register(_ c: Credentials) async throws -> AuthResponse {
        try await call("/api/auth/register", method: "POST", body: try encode(c))
    }

    public func login(_ r: LoginRequest) async throws -> AuthResponse {
        try await call("/api/auth/login", method: "POST", body: try encode(r))
    }

    public func register(_ r: RegisterRequest) async throws -> AuthResponse {
        try await call("/api/auth/register", method: "POST", body: try encode(r))
    }

    public func sendEmailCode(email: String) async throws -> CodeSentResponse {
        try await call("/api/auth/email/send-code", method: "POST", body: try encode(EmailCodeRequest(email: email)))
    }

    public func loginWithEmailCode(email: String, code: String) async throws -> AuthResponse {
        try await call("/api/auth/email/login", method: "POST",
                       body: try encode(EmailCodeLoginRequest(email: email, code: code)))
    }

    public func sendVerificationEmail() async throws -> CodeSentResponse {
        try await call("/api/me/email/send-verification", method: "POST")
    }

    public func verifyEmail(code: String) async throws -> User {
        try await call("/api/me/email/verify", method: "POST", body: try encode(EmailVerifyRequest(code: code)))
    }

    public func refresh(refreshToken: String) async throws -> AuthResponse {
        try await call("/api/auth/refresh", method: "POST", body: try encode(RefreshRequest(refreshToken: refreshToken)))
    }

    public func logout(refreshToken: String) async throws -> OKResponse {
        try await call("/api/auth/logout", method: "POST", body: try encode(RefreshRequest(refreshToken: refreshToken)))
    }

    public func me() async throws -> User { try await call("/api/me") }

    public func updateNickname(_ nickname: String) async throws -> User {
        try await call("/api/me", method: "PATCH", body: try encode(["nickname": nickname]))
    }

    // MARK: - Avatars（multipart JPEG 上传；GET 返回图片字节）
    public func uploadMyAvatar(jpeg: Data) async throws -> User {
        try await upload("/api/me/avatar", jpeg: jpeg)
    }

    public func myAvatarData() async throws -> Data { try await fetchBytes("/api/me/avatar") }

    public func deleteMyAvatar() async throws -> User {
        try await call("/api/me/avatar", method: "DELETE")
    }

    public func uploadBotAvatar(botID: Int, jpeg: Data) async throws -> Bot {
        try await upload("/api/bots/\(botID)/avatar", jpeg: jpeg)
    }

    public func botAvatarData(botID: Int) async throws -> Data {
        try await fetchBytes("/api/bots/\(botID)/avatar")
    }

    public func deleteBotAvatar(botID: Int) async throws -> Bot {
        try await call("/api/bots/\(botID)/avatar", method: "DELETE")
    }

    // MARK: - Bots
    public func bots() async throws -> BotsResponse { try await call("/api/bots") }

    public func createBot(_ b: BotCreate) async throws -> Bot {
        try await call("/api/bots", method: "POST", body: try encode(b))
    }

    public func deleteBot(_ id: Int) async throws -> OKResponse {
        try await call("/api/bots/\(id)", method: "DELETE")
    }

    public func updateBot(_ id: Int, _ patch: BotPatch) async throws -> Bot {
        try await call("/api/bots/\(id)", method: "PATCH", body: try encode(patch))
    }

    public func tools() async throws -> ToolsResponse { try await call("/api/tools") }

    public func mcpCatalog() async throws -> MCPCatalogResponse { try await call("/api/mcp/catalog") }

    public func mcpServers() async throws -> MCPServersResponse { try await call("/api/mcp/servers") }

    public func addMCPServer(catalogID: String) async throws -> MCPServer {
        try await call("/api/mcp/servers", method: "POST", body: try encode(["catalog_id": catalogID]))
    }

    public func updateMCPServer(id: Int, enabled: Bool) async throws -> MCPServer {
        try await call("/api/mcp/servers/\(id)", method: "PATCH", body: try encode(["enabled": enabled]))
    }

    public func setMCPConsent(id: Int, granted: Bool) async throws -> MCPServer {
        try await call("/api/mcp/servers/\(id)/consent", method: "POST", body: try encode(["granted": granted]))
    }

    public func deleteMCPServer(id: Int) async throws -> OKResponse {
        try await call("/api/mcp/servers/\(id)", method: "DELETE")
    }

    public func syncMCPServer(id: Int) async throws -> MCPSyncResult {
        try await call("/api/mcp/servers/\(id)/sync", method: "POST")
    }

    public func startMCPOAuth(serverID: Int) async throws -> MCPOAuthStart {
        try await call("/api/mcp/servers/\(serverID)/auth/start", method: "POST")
    }

    public func completeMCPOAuth(serverID: Int, callback: MCPOAuthCallback) async throws -> MCPOAuthResult {
        try await call("/api/mcp/servers/\(serverID)/auth/callback", method: "POST", body: try encode(callback))
    }

    public func cancelMCPOAuth(serverID: Int, state: String) async throws {
        let _: OKResponse = try await call("/api/mcp/servers/\(serverID)/auth/cancel", method: "POST",
                                           body: try encode(["state": state]))
    }

    public func disconnectMCPOAuth(serverID: Int) async throws {
        let _: OKResponse = try await call("/api/mcp/servers/\(serverID)/auth", method: "DELETE")
    }

    public func mcpTools(serverID: Int) async throws -> MCPToolsResponse {
        try await call("/api/mcp/servers/\(serverID)/tools")
    }

    // 插件与其他 /api 请求一样走 call，使用同一个 URLSession。
    public func pluginCatalog() async throws -> PluginCatalogResponse {
        try await call("/api/plugins/catalog")
    }

    public func plugins() async throws -> PluginsResponse { try await call("/api/plugins") }

    public func plugin(id: String) async throws -> Plugin { try await call("/api/plugins/\(id)") }

    public func installPlugin(id: String) async throws -> Plugin {
        try await call("/api/plugins/\(id)/install", method: "POST")
    }

    public func uninstallPlugin(id: String) async throws -> PluginUninstallResult {
        try await call("/api/plugins/\(id)", method: "DELETE")
    }

    public func updatePlugin(id: String, enabled: Bool) async throws -> Plugin {
        try await call("/api/plugins/\(id)", method: "PATCH", body: try encode(["enabled": enabled]))
    }

    public func setPluginConsent(id: String, granted: Bool) async throws -> Plugin {
        try await call("/api/plugins/\(id)/consent", method: "POST", body: try encode(["granted": granted]))
    }

    public func pluginTools(id: String) async throws -> PluginToolsResponse {
        try await call("/api/plugins/\(id)/tools")
    }

    public func syncPlugin(id: String) async throws -> PluginSyncResult {
        try await call("/api/plugins/\(id)/sync", method: "POST")
    }

    public func setPluginCredential(id: String, token: String) async throws -> Plugin {
        try await call("/api/plugins/\(id)/credential", method: "PUT", body: try encode(["token": token]))
    }

    public func deletePluginCredential(id: String) async throws -> Plugin {
        try await call("/api/plugins/\(id)/credential", method: "DELETE")
    }

    public func acceptPluginToolChanges(id: String) async throws -> PluginAcceptChangesResult {
        try await call("/api/plugins/\(id)/accept-tool-changes", method: "POST")
    }

    public func delegations(botID: Int) async throws -> DelegationsResponse {
        try await call("/api/bots/\(botID)/delegations")
    }

    public func messages(botID: Int) async throws -> MessagesResponse {
        try await call("/api/bots/\(botID)/messages")
    }

    public func clearMessages(botID: Int, includeMemories: Bool) async throws -> ClearMessagesResponse {
        try await call("/api/bots/\(botID)/messages", method: "DELETE",
                       query: includeMemories ? [URLQueryItem(name: "include_memories", value: "true")] : [])
    }

    public func deleteMessage(botID: Int, messageID: Int) async throws -> OKResponse {
        try await call("/api/bots/\(botID)/messages/\(messageID)", method: "DELETE")
    }

    public func setMessageFeedback(messageID: Int, rating: Int, reason: String?) async throws -> MessageFeedbackResponse {
        try await call("/api/messages/\(messageID)/feedback", method: "POST",
                       body: try encode(MessageFeedbackWrite(rating: rating, reason: reason)))
    }

    public func deleteMessageFeedback(messageID: Int) async throws -> OKResponse {
        try await call("/api/messages/\(messageID)/feedback", method: "DELETE")
    }

    // MARK: - Memories（长期记忆，见 docs/design/MEMORY_GROWTH.md §5.5）
    public func memories(_ query: MemoryQuery) async throws -> MemoriesResponse {
        try await call("/api/memories", query: query.queryItems)
    }

    public func memory(id: Int) async throws -> Memory { try await call("/api/memories/\(id)") }

    public func createMemory(_ m: MemoryCreate) async throws -> Memory {
        try await call("/api/memories", method: "POST", body: try encode(m))
    }

    public func updateMemory(id: Int, _ patch: MemoryPatch) async throws -> Memory {
        try await call("/api/memories/\(id)", method: "PATCH", body: try encode(patch))
    }

    public func deleteMemory(id: Int) async throws -> OKResponse {
        try await call("/api/memories/\(id)", method: "DELETE")
    }

    public func clearMemories(scope: MemoryScope?, botID: Int?) async throws -> MemoryClearResponse {
        var q = [URLQueryItem(name: "scope", value: scope?.rawValue ?? "all"), URLQueryItem(name: "confirm", value: "true")]
        if let botID { q.append(URLQueryItem(name: "bot_id", value: String(botID))) }
        return try await call("/api/memories", method: "DELETE", query: q)
    }

    public func confirmMemory(id: Int, content: String?) async throws -> MemoryConfirmResult {
        let body: Data? = try content.map { try encode(["content": $0]) }
        return try await call("/api/memories/\(id)/confirm", method: "POST", body: body)
    }

    public func rejectMemory(id: Int) async throws -> OKResponse {
        try await call("/api/memories/\(id)/reject", method: "POST")
    }

    public func memorySettings() async throws -> MemorySettings { try await call("/api/memory/settings") }

    public func updateMemorySettings(enabled: Bool) async throws -> MemorySettings {
        try await call("/api/memory/settings", method: "PATCH", body: try encode(["enabled": enabled]))
    }

    public func botGrowth(botID:Int) async throws -> BotGrowth { try await call("/api/bots/\(botID)/growth") }
    public func monthlyMemoryReview(month:String) async throws -> MonthlyMemoryReview {
        try await call("/api/review/monthly", query:[URLQueryItem(name:"month",value:month)])
    }
    public func memoryReferences(messageID:Int) async throws -> MemoryReferencesResponse { try await call("/api/messages/\(messageID)/memories") }
    public func memoryExport() async throws -> MemoryExportResponse { try await call("/api/memories/export") }

    public func memorySuggestions(botID: Int) async throws -> MemorySuggestionsResponse {
        try await call("/api/bots/\(botID)/suggestions")
    }

    public func decideMemorySuggestion(id: Int, accept: Bool) async throws -> SuggestionDecisionResponse {
        let action = accept ? "accept" : "dismiss"
        return try await call("/api/suggestions/\(id)/\(action)", method: "POST", body: Data("{}".utf8))
    }

    public func quickPrompts(botID: Int) async throws -> QuickPromptsResponse {
        try await call("/api/bots/\(botID)/quick-prompts")
    }

    // MARK: - Reminders / Quota
    public func reminders() async throws -> RemindersResponse { try await call("/api/reminders") }

    public func reminder(id: Int) async throws -> Reminder { try await call("/api/reminders/\(id)") }

    public func createReminder(_ body: ReminderWrite) async throws -> Reminder {
        try await call("/api/reminders", method: "POST", body: try encode(body), headers: idempotency(nil))
    }

    public func updateReminder(id: Int, _ body: ReminderWrite) async throws -> Reminder {
        try await call("/api/reminders/\(id)", method: "PATCH", body: try encode(body), headers: idempotency(nil))
    }

    public func completeReminder(_ id: Int, idempotencyKey: String? = nil) async throws -> Reminder {
        try await call("/api/reminders/\(id)/complete", method: "POST", body: Data("{}".utf8), headers: idempotency(idempotencyKey))
    }

    public func snoozeReminder(_ id: Int, minutes: Int? = nil, until: String? = nil, idempotencyKey: String? = nil) async throws -> Reminder {
        try await call("/api/reminders/\(id)/snooze", method: "POST", body: try encode(SnoozeBody(minutes: minutes, until: until)),
                       headers: idempotency(idempotencyKey))
    }

    public func reopenReminder(_ id: Int) async throws -> Reminder {
        try await call("/api/reminders/\(id)/reopen", method: "POST", body: Data("{}".utf8), headers: idempotency(nil))
    }

    public func skipReminder(_ id: Int) async throws -> Reminder {
        try await call("/api/reminders/\(id)/skip", method: "POST", body: Data("{}".utf8), headers: idempotency(nil))
    }

    public func restoreReminder(_ id: Int) async throws -> Reminder {
        try await call("/api/reminders/\(id)/restore", method: "POST", body: Data("{}".utf8), headers: idempotency(nil))
    }

    public func deleteReminder(_ id: Int, scope: String = "series") async throws -> Reminder {
        try await call("/api/reminders/\(id)", method: "DELETE", query: [URLQueryItem(name: "scope", value: scope)], headers: idempotency(nil))
    }

    public func notifications(unread: Bool = false, category: String? = nil) async throws -> NotificationsResponse {
        var query: [URLQueryItem] = []
        if unread { query.append(URLQueryItem(name: "unread", value: "true")) }
        if let category { query.append(URLQueryItem(name: "category", value: category)) }
        return try await call("/api/notifications", query: query)
    }

    public func notificationSummary() async throws -> NotificationSummary { try await call("/api/notifications/summary") }

    public func markNotificationRead(_ id: Int) async throws -> InboxNotification {
        try await call("/api/notifications/\(id)/read", method: "POST")
    }

    public func markNotificationUnread(_ id: Int) async throws -> InboxNotification {
        try await call("/api/notifications/\(id)/unread", method: "POST")
    }

    public func markAllNotificationsRead() async throws -> OKResponse {
        try await call("/api/notifications/read-all", method: "POST", body: Data("{}".utf8))
    }

    public func deleteNotification(_ id: Int) async throws -> OKResponse {
        try await call("/api/notifications/\(id)", method: "DELETE")
    }

    public func reportNotification(id: Int, event: String, channel: String, deviceId: String?) async throws -> OKResponse {
        try await call("/api/notifications/\(id)/events", method: "POST",
                       body: try encode(DeliveryEventBody(event: event, channel: channel, deviceId: deviceId)))
    }

    public func notificationSettings() async throws -> NotificationSettings { try await call("/api/notification-settings") }

    public func updateNotificationSettings(_ body: NotificationSettings) async throws -> NotificationSettings {
        try await call("/api/notification-settings", method: "PATCH", body: try encode(body))
    }

    public func registerDevice(_ body: DeviceRegistration) async throws -> DeviceRegistration {
        try await call("/api/devices", method: "POST", body: try encode(body))
    }

    public func deleteDevice(_ deviceId: String) async throws -> OKResponse {
        let encoded = deviceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceId
        return try await call("/api/devices/\(encoded)", method: "DELETE")
    }

    private func idempotency(_ key: String?) -> [String: String] {
        ["Idempotency-Key": key ?? UUID().uuidString]
    }

    public func quota() async throws -> Quota { try await call("/api/quota") }

    public func health() async throws -> HealthStatus { try await call("/api/health") }

    // MARK: - Streaming chat (SSE)
    public func chatStream(botID: Int, message: String) -> AsyncThrowingStream<ChatEvent, Error> {
        chatStream(botID: botID, message: message, attachmentIDs: [])
    }

    /// attachmentIDs：先 `uploadAttachment` 拿到的 id（最多 1 个）；有图时 message 可以为空。
    public func chatStream(botID: Int, message: String, attachmentIDs: [String]) -> AsyncThrowingStream<ChatEvent, Error> {
        let body: Data
        do {
            body = try encode(ChatRequest(message: message, attachmentIDs: attachmentIDs))
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let path = "/api/bots/\(botID)/chat"

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // swift-corelibs-foundation（Linux）没有 URLSession.bytes；iOS/macOS 路径不变。
                    #if os(Linux)
                    throw APIError(status: 0, message: "当前平台不支持流式聊天")
                    #else
                    func open(_ token: String?) async throws -> (URLSession.AsyncBytes, Int) {
                        var r = makeRequest(path, method: "POST", body: body, token: token)
                        r.setValue("ios", forHTTPHeaderField: "X-VeraBot-Client")
                        r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        r.timeoutInterval = 180
                        let (bytes, response) = try await urlSession.bytes(for: r)
                        return (bytes, (response as? HTTPURLResponse)?.statusCode ?? 0)
                    }
                    let sent = token
                    var (bytes, status) = try await open(sent)
                    if status == 401, let fresh = await refreshedToken(after: sent, path: path) {
                        (bytes, status) = try await open(fresh)
                    }
                    guard status == 200 else {
                        var data = Data()
                        for try await b in bytes { data.append(b) }
                        throw Self.apiError(status: status, data: data)
                    }
                    var event = "message"
                    // 注意：AsyncLineSequence 会跳过空行，因此在收到 data 行时立即分发。
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let payload = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
                            if let ev = Self.parse(event: event, data: payload) {
                                continuation.yield(ev)
                            }
                        }
                    }
                    continuation.finish()
                    #endif
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func parse(event: String, data: Data) -> ChatEvent? {
        let decoder = JSONDecoder()
        switch event {
        case "delta":
            return (try? decoder.decode(DeltaPayload.self, from: data)).map { .delta($0.text) }
        case "tool_start":
            return (try? decoder.decode(ToolTrace.self, from: data)).map { .toolStart($0) }
        case "tool_result":
            return (try? decoder.decode(ToolTrace.self, from: data)).map { .toolResult($0) }
        case "status":
            return (try? decoder.decode(ChatStatus.self, from: data)).map { .status($0) }
        case "confirmation_required":
            return (try? decoder.decode(ConfirmationRequired.self, from: data)).map { .confirmationRequired($0) }
        case "error":
            return .error((try? decoder.decode(ErrorPayload.self, from: data))?.message ?? "未知错误")
        case "done":
            return .done((try? decoder.decode(ChatDone.self, from: data)) ?? ChatDone())
        case "notification":
            return (try? decoder.decode(ChatNotification.self, from: data)).map { .notification($0) }
        default:
            return nil
        }
    }

    // MARK: - Plumbing
    func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    func makeRequest(_ path: String, method: String, body: Data?, query: [URLQueryItem] = [],
                             token: String?, headers: [String: String] = [:]) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url = url.appending(queryItems: query) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ios", forHTTPHeaderField: "X-VeraBot-Client")
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        req.timeoutInterval = 30
        return req
    }

    /// 401 后的透明刷新：只对非 /api/auth/ 请求、且有 session + 刷新令牌时生效；返回新访问令牌或 nil。
    func refreshedToken(after sent: String?, path: String) async -> String? {
        guard let session, !path.hasPrefix("/api/auth/") else { return nil }
        if case .refreshed(let t) = await session.refresh(after: sent, baseURL: baseURL) { return t.access }
        return nil
    }

    /// 发送请求；401 时刷新一次令牌后用同样的请求重试。
    func send(_ path: String, _ build: (String?) -> URLRequest) async throws -> (Data, Int) {
        let sent = token
        var (data, response) = try await urlSession.data(for: build(sent))
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, let fresh = await refreshedToken(after: sent, path: path) {
            (data, response) = try await urlSession.data(for: build(fresh))
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        return (data, status)
    }

    func call<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil,
                                               query: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> T {
        let (data, status) = try await send(path) {
            makeRequest(path, method: method, body: body, query: query, token: $0, headers: headers)
        }
        guard (200..<300).contains(status) else {
            throw Self.apiError(status: status, data: data)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func upload<T: Decodable & Sendable>(_ path: String, jpeg: Data) async throws -> T {
        let boundary = "VeraBotBoundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n--\(boundary)--\r\n")
        let payload = body
        let (data, status) = try await send(path) { token in
            var req = URLRequest(url: baseURL.appending(path: path))
            req.httpMethod = "POST"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.setValue("ios", forHTTPHeaderField: "X-VeraBot-Client")
            if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            req.httpBody = payload
            req.timeoutInterval = 60
            return req
        }
        guard (200..<300).contains(status) else { throw Self.apiError(status: status, data: data) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetchBytes(_ path: String) async throws -> Data {
        let (data, status) = try await send(path) { token in
            var req = URLRequest(url: baseURL.appending(path: path))
            req.httpMethod = "GET"
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue("ios", forHTTPHeaderField: "X-VeraBot-Client")
            if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            req.timeoutInterval = 30
            return req
        }
        guard (200..<300).contains(status) else { throw Self.apiError(status: status, data: data) }
        return data
    }

    static func apiError(status: Int, data: Data) -> APIError {
        var message = "请求失败（HTTP \(status)）"
        var code: String?
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let detail = body.detail {
            switch detail {
            case .string(let s):
                message = s
            case .array(let items):
                message = items.map { ($0["msg"]?.text) ?? $0.text }.joined(separator: "；")
            case .object:
                // {"detail": {"message": "…", "code": "…"}}（记忆等需要区分原因的接口）
                message = detail["message"]?.text ?? detail.text
                code = detail["code"]?.text
            default:
                message = detail.text
            }
        }
        return APIError(status: status, message: message, code: code)
    }
}
