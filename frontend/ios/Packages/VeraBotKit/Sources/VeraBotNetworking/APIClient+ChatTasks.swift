import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import VeraBotCore

extension APIClient {
    public func submitChatInput(botID: Int, input: ChatInputRequest) async throws -> ChatInputReceipt { try await continuityCall("/api/bots/\(botID)/chat/inputs", method: "POST", body: try encode(input)) }
    public func chatInputReceipt(botID: Int, requestID: String) async throws -> ChatInputReceipt {
        guard !requestID.contains("/"), !requestID.contains("?"), !requestID.contains("#") else { throw APIError(status: 400, message: "无效请求标识") }
        return try await continuityCall("/api/bots/\(botID)/chat/inputs/\(requestID)")
    }
    public func chatExecution(botID: Int) async throws -> ChatExecutionSnapshot { try await continuityCall("/api/bots/\(botID)/chat/execution") }
    public func stopChatTask(botID: Int, taskID: Int, version: Int, requestID: String) async throws -> ChatTaskControl {
        try await continuityCall("/api/bots/\(botID)/chat/tasks/\(taskID)/stop", method: "POST", body: try encode(StopRequest(expected_version: version, control_request_id: requestID)))
    }
    public func answerChatTask(botID: Int, taskID: Int, version: Int, waitID: String, message: String, requestID: String) async throws -> ChatTaskControl {
        try await continuityCall("/api/bots/\(botID)/chat/tasks/\(taskID)/inputs", method: "POST", body: try encode(AnswerRequest(client_request_id: requestID, expected_version: version, wait_id: waitID, message: message)))
    }
    public func conversationActivity() async throws -> ConversationActivitySnapshot { try await continuityCall("/api/conversations/activity") }
    public func readConversation(kind: String, id: Int, generation: Int, messages: [MessagePublication]) async throws -> ConversationReadResponse {
        guard ["private", "group"].contains(kind) else { throw APIError(status: 400, message: "无效会话类型") }
        return try await continuityCall("/api/conversations/\(kind)/\(id)/read", method: "POST", body: try encode(ReadRequest(generation: generation, messages: messages)))
    }
    public func conversationEvents(afterID: Int) -> AsyncThrowingStream<DurableEvent, Error> { durableEvents("/api/conversations/events", afterID: afterID) }
    public func chatEvents(botID: Int, afterID: Int) -> AsyncThrowingStream<DurableEvent, Error> { durableEvents("/api/bots/\(botID)/chat/events", afterID: afterID) }

    private func continuityCall<Value: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Value {
        let generation = session?.generation
        let value: Value = try await call(path, method: method, body: body)
        try Task.checkCancellation()
        if let generation, session?.isCurrent(generation) != true { throw CancellationError() }
        return value
    }

    private func durableEvents(_ path: String, afterID: Int) -> AsyncThrowingStream<DurableEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let generation = session?.generation
                    func checkScope() throws { try Task.checkCancellation(); if let generation, session?.isCurrent(generation) != true { throw CancellationError() } }
                    func request(_ token: String?) -> URLRequest {
                        var value = makeRequest(path, method: "GET", body: nil, query: [URLQueryItem(name: "after_id", value: String(afterID))], token: token)
                        value.setValue("text/event-stream", forHTTPHeaderField: "Accept"); value.timeoutInterval = 300
                        return value
                    }
                    #if os(Linux)
                    let (data, status) = try await send(path, request)
                    try checkScope()
                    guard (200..<300).contains(status) else { throw Self.apiError(status: status, data: data) }
                    var parser = DurableSSEParser()
                    for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") { if let event = parser.line(line) { continuation.yield(event) } }
                    #else
                    let sent = token
                    var (bytes, response) = try await urlSession.bytes(for: request(sent))
                    try checkScope()
                    if (response as? HTTPURLResponse)?.statusCode == 401, let fresh = await refreshedToken(after: sent, path: path, generation: generation) {
                        (bytes, response) = try await urlSession.bytes(for: request(fresh)); try checkScope()
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var data = Data(); for try await byte in bytes { data.append(byte); if data.count > 65536 { break } }
                        throw Self.apiError(status: status, data: data)
                    }
                    var parser = DurableSSEParser()
                    for try await line in bytes.lines { try checkScope(); if let event = parser.line(line) { continuation.yield(event) } }
                    #endif
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
private struct StopRequest: Encodable { let expected_version: Int; let control_request_id: String }
private struct AnswerRequest: Encodable { let client_request_id: String; let expected_version: Int; let wait_id: String; let message: String }
private struct ReadRequest: Encodable { let generation: Int; let messages: [MessagePublication] }

public struct DurableSSEParser: Sendable {
    private var id: Int?
    private var name = "message"
    private var data: [String] = []
    public init() {}
    public mutating func line(_ raw: String) -> DurableEvent? {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if line.isEmpty {
            defer { id = nil; name = "message"; data.removeAll() }
            guard let id, !data.isEmpty else { return nil }
            return DurableEvent(id: id, name: name, data: Data(data.joined(separator: "\n").utf8))
        }
        if line.hasPrefix(":") { return nil }
        let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard pair.count == 2 else { return nil }
        let value = pair[1].hasPrefix(" ") ? String(pair[1].dropFirst()) : String(pair[1])
        switch pair[0] { case "id": id = Int(value); case "event": name = value; case "data": data.append(value); default: break }
        return nil
    }
}
