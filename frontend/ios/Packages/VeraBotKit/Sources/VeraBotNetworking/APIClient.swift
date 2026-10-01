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
    case error(String)
    case done(ChatDone)
}

/// SSE done 事件：本条回复的消息 id，以及本轮注入了哪些记忆（v4 起，旧后端为空）。
public struct ChatDone: Decodable, Sendable, Hashable {
    public let messageID: Int?
    public let memoryIDs: [Int]

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case memoryIDs = "memory_ids"
    }

    public init(messageID: Int? = nil, memoryIDs: [Int] = []) {
        self.messageID = messageID
        self.memoryIDs = memoryIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageID = try c.decodeIfPresent(Int.self, forKey: .messageID)
        memoryIDs = try c.decodeIfPresent([Int].self, forKey: .memoryIDs) ?? []
    }
}

private struct DeltaPayload: Decodable { let text: String }
private struct ErrorPayload: Decodable { let message: String }
private struct ErrorBody: Decodable { let detail: JSONValue? }

/// VeraBotAPI 的 HTTP 实现：无状态值类型、Sendable，可安全跨并发域传递。
public struct APIClient: VeraBotAPI {
    public let baseURL: URL
    public let token: String?

    public init(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
    }

    // MARK: - Auth
    public func login(_ c: Credentials) async throws -> AuthResponse {
        try await call("/api/auth/login", method: "POST", body: try encode(c))
    }

    public func register(_ c: Credentials) async throws -> AuthResponse {
        try await call("/api/auth/register", method: "POST", body: try encode(c))
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

    // MARK: - Reminders / Quota
    public func reminders() async throws -> RemindersResponse { try await call("/api/reminders") }

    public func completeReminder(_ id: Int) async throws -> OKResponse {
        try await call("/api/reminders/\(id)/done", method: "POST")
    }

    public func quota() async throws -> Quota { try await call("/api/quota") }

    public func health() async throws -> HealthStatus { try await call("/api/health") }

    // MARK: - Streaming chat (SSE)
    public func chatStream(botID: Int, message: String) -> AsyncThrowingStream<ChatEvent, Error> {
        let request: URLRequest
        do {
            let body = try encode(["message": message])
            var r = makeRequest("/api/bots/\(botID)/chat", method: "POST", body: body)
            r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            r.timeoutInterval = 180
            request = r
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // swift-corelibs-foundation（Linux）没有 URLSession.bytes；iOS/macOS 路径不变。
                    #if os(Linux)
                    throw APIError(status: 0, message: "当前平台不支持流式聊天")
                    #else
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
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

    private static func parse(event: String, data: Data) -> ChatEvent? {
        let decoder = JSONDecoder()
        switch event {
        case "delta":
            return (try? decoder.decode(DeltaPayload.self, from: data)).map { .delta($0.text) }
        case "tool_start":
            return (try? decoder.decode(ToolTrace.self, from: data)).map { .toolStart($0) }
        case "tool_result":
            return (try? decoder.decode(ToolTrace.self, from: data)).map { .toolResult($0) }
        case "error":
            return .error((try? decoder.decode(ErrorPayload.self, from: data))?.message ?? "未知错误")
        case "done":
            return .done((try? decoder.decode(ChatDone.self, from: data)) ?? ChatDone())
        default:
            return nil
        }
    }

    // MARK: - Plumbing
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func makeRequest(_ path: String, method: String, body: Data?, query: [URLQueryItem] = []) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url = url.appending(queryItems: query) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        req.timeoutInterval = 30
        return req
    }

    private func call<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil,
                                               query: [URLQueryItem] = []) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: makeRequest(path, method: method, body: body, query: query))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
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
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        req.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.apiError(status: status, data: data) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func fetchBytes(_ path: String) async throws -> Data {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
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
