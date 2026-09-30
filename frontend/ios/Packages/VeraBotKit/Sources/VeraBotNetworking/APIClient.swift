// VeraBotNetworking：REST + SSE 客户端。
import Foundation
import VeraBotCore

public struct APIError: LocalizedError, Sendable {
    public let status: Int
    public let message: String

    public init(status: Int, message: String) {
        self.status = status
        self.message = message
    }
    public var errorDescription: String? { message }
}

/// SSE 事件（与后端 /api/bots/{id}/chat 对应）。
public enum ChatEvent: Sendable {
    case delta(String)
    case toolStart(ToolTrace)
    case toolResult(ToolTrace)
    case error(String)
    case done
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

    public func clearMessages(botID: Int) async throws -> OKResponse {
        try await call("/api/bots/\(botID)/messages", method: "DELETE")
    }

    // MARK: - Reminders / Quota
    public func reminders() async throws -> RemindersResponse { try await call("/api/reminders") }

    public func completeReminder(_ id: Int) async throws -> OKResponse {
        try await call("/api/reminders/\(id)/done", method: "POST")
    }

    public func quota() async throws -> Quota { try await call("/api/quota") }

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
            return .done
        default:
            return nil
        }
    }

    // MARK: - Plumbing
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func makeRequest(_ path: String, method: String, body: Data?) -> URLRequest {
        var req = URLRequest(url: baseURL.appending(path: path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        req.timeoutInterval = 30
        return req
    }

    private func call<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: makeRequest(path, method: method, body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Self.apiError(status: status, data: data)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func apiError(status: Int, data: Data) -> APIError {
        var message = "请求失败（HTTP \(status)）"
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let detail = body.detail {
            switch detail {
            case .string(let s):
                message = s
            case .array(let items):
                message = items.map { ($0["msg"]?.text) ?? $0.text }.joined(separator: "；")
            default:
                message = detail.text
            }
        }
        return APIError(status: status, message: message)
    }
}
