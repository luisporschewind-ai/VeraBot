import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import VeraBotCore

public protocol GroupChatAPI: Sendable {
    func groups() async throws -> GroupListResponse
    func createGroup(_ request: GroupCreateRequest) async throws -> ChatGroup
    func group(id: Int) async throws -> ChatGroup
    func updateGroup(id: Int, request: GroupUpdateRequest) async throws -> ChatGroup
    func deleteGroup(id: Int) async throws -> OKResponse
    func groupMessages(groupID: Int, beforeID: Int?) async throws -> GroupMessagesResponse
    func syncGroupMessages(groupID: Int, beforeID: Int?, expectedRevision: Int64?) async throws -> GroupMessagesSyncResponse
    func clearGroupMessages(groupID: Int) async throws -> OKResponse
    func groupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn
    func stopGroupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn
    func groupChatStream(groupID: Int, request: GroupChatRequest) -> AsyncThrowingStream<GroupChatEvent, Error>
    func retryGroupMessage(groupID: Int, messageID: Int, requestID: UUID) -> AsyncThrowingStream<GroupChatEvent, Error>
}

public extension GroupChatAPI {
    func syncGroupMessages(groupID: Int, beforeID: Int?, expectedRevision: Int64?) async throws -> GroupMessagesSyncResponse {
        throw APIError(status: 501, message: "当前服务不支持离线历史同步")
    }
}

/// The caller restores this authoritative snapshot instead of resending a new UUID.
public struct GroupRequestExists: Error, Sendable {
    public let turn: GroupTurn
}

extension APIClient: GroupChatAPI {
    func checkGroupSession(_ generation: UInt64?) throws {
        try Task.checkCancellation()
        if let generation, let session, !session.isCurrent(generation) { throw CancellationError() }
    }
    private func groupCall<T: Decodable & Sendable>(_ path: String, method: String = "GET", body: Data? = nil,
                                                   query: [URLQueryItem] = [], generation expected: UInt64? = nil) async throws -> T {
        let generation = expected ?? session?.generation
        try checkGroupSession(generation)
        do {
            let value: T = try await call(path, method: method, body: body, query: query)
            try checkGroupSession(generation)
            return value
        } catch {
            try checkGroupSession(generation)
            throw error
        }
    }
    public func groups() async throws -> GroupListResponse { try await groupCall("/api/groups") }
    public func createGroup(_ request: GroupCreateRequest) async throws -> ChatGroup {
        try await groupCall("/api/groups", method: "POST", body: try encode(request))
    }
    public func group(id: Int) async throws -> ChatGroup { try await groupCall("/api/groups/\(id)") }
    public func updateGroup(id: Int, request: GroupUpdateRequest) async throws -> ChatGroup {
        try await groupCall("/api/groups/\(id)", method: "PATCH", body: try encode(request))
    }
    public func deleteGroup(id: Int) async throws -> OKResponse { try await groupCall("/api/groups/\(id)", method: "DELETE") }
    public func groupMessages(groupID: Int, beforeID: Int? = nil) async throws -> GroupMessagesResponse {
        try await groupCall("/api/groups/\(groupID)/messages", query: beforeID.map { [URLQueryItem(name: "before_id", value: String($0))] } ?? [])
    }
    public func syncGroupMessages(groupID: Int, beforeID: Int? = nil, expectedRevision: Int64? = nil) async throws -> GroupMessagesSyncResponse {
        var query = [URLQueryItem(name: "limit", value: "100")]
        if let beforeID { query.append(URLQueryItem(name: "before_id", value: String(beforeID))) }
        if let expectedRevision { query.append(URLQueryItem(name: "expected_revision", value: String(expectedRevision))) }
        return try await groupCall("/api/groups/\(groupID)/messages/sync", query: query)
    }
    public func clearGroupMessages(groupID: Int) async throws -> OKResponse { try await groupCall("/api/groups/\(groupID)/messages", method: "DELETE") }
    public func groupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn { try await groupCall("/api/groups/\(groupID)/turns/\(turnID)") }
    public func stopGroupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn { try await groupCall("/api/groups/\(groupID)/turns/\(turnID)/stop", method: "POST") }
    public func groupChatStream(groupID: Int, request: GroupChatRequest) -> AsyncThrowingStream<GroupChatEvent, Error> {
        groupStream(groupID: groupID, path: "/api/groups/\(groupID)/chat", body: Result { try encode(request) })
    }
    public func retryGroupMessage(groupID: Int, messageID: Int, requestID: UUID) -> AsyncThrowingStream<GroupChatEvent, Error> {
        struct RetryRequest: Encodable { let client_request_id: UUID }
        return groupStream(groupID: groupID, path: "/api/groups/\(groupID)/messages/\(messageID)/retry",
                           body: Result { try encode(RetryRequest(client_request_id: requestID)) })
    }

    private func groupStream(groupID: Int, path: String, body: Result<Data, Error>) -> AsyncThrowingStream<GroupChatEvent, Error> {
        let generation = session?.generation
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try checkGroupSession(generation)
                    let payload = try body.get()
                    func build(_ token: String?) -> URLRequest {
                        var r = makeRequest(path, method: "POST", body: payload, token: token, headers: ["Accept": "text/event-stream"])
                        r.timeoutInterval = 300
                        return r
                    }
                    var parser = GroupSSEDecoder()
                    var completed = false
                    var acceptedTurnID: Int?
                    func consume(_ line: String) throws {
                        try checkGroupSession(generation)
                        guard let event = parser.consume(line), event.groupID == groupID else { return }
                        if let acceptedTurnID, acceptedTurnID != event.turnID { return }
                        acceptedTurnID = event.turnID
                        continuation.yield(event)
                        if case .turnDone = event.payload { completed = true }
                    }
                    let sent = token
                    #if canImport(FoundationNetworking)
                    var (data, response) = try await urlSession.data(for: build(sent))
                    try checkGroupSession(generation)
                    var status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 401, let fresh = await refreshedToken(after: sent, path: path, generation: generation) {
                        try checkGroupSession(generation)
                        (data, response) = try await urlSession.data(for: build(fresh))
                        status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    }
                    try checkGroupSession(generation)
                    if !(200..<300).contains(status) { try await handleGroupStreamError(groupID: groupID, status: status, data: data, generation: generation) }
                    for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
                        try consume(line.hasSuffix("\r") ? String(line.dropLast()) : line)
                        if completed { break }
                    }
                    #else
                    var (bytes, response) = try await urlSession.bytes(for: build(sent))
                    try checkGroupSession(generation)
                    var status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 401, let fresh = await refreshedToken(after: sent, path: path, generation: generation) {
                        try checkGroupSession(generation)
                        (bytes, response) = try await urlSession.bytes(for: build(fresh))
                        status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    }
                    try checkGroupSession(generation)
                    if !(200..<300).contains(status) {
                        var data = Data()
                        for try await byte in bytes {
                            try checkGroupSession(generation)
                            data.append(byte)
                            if data.count >= 65_536 { break }
                        }
                        try await handleGroupStreamError(groupID: groupID, status: status, data: data, generation: generation)
                    }
                    // AsyncLineSequence skips empty lines; SSE needs the blank frame separator.
                    var line = Data()
                    for try await byte in bytes {
                        try checkGroupSession(generation)
                        if byte == 10 {
                            if line.last == 13 { line.removeLast() }
                            try consume(String(decoding: line, as: UTF8.self))
                            line.removeAll(keepingCapacity: true)
                            if completed { break }
                        } else {
                            line.append(byte)
                            if line.count > 1_048_576 { throw APIError(status: 0, message: "群聊事件过大", code: "group_event_invalid") }
                        }
                    }
                    #endif
                    try checkGroupSession(generation)
                    guard completed else { throw APIError(status: 0, message: "讨论连接已中断，请重新加载记录", code: "group_stream_interrupted") }
                    continuation.finish()
                } catch {
                    if let generation, let session, !session.isCurrent(generation) {
                        continuation.finish(throwing: CancellationError())
                    } else { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    private func handleGroupStreamError(groupID: Int, status: Int, data: Data, generation: UInt64?) async throws {
        try checkGroupSession(generation)
        let error = Self.apiError(status: status, data: data)
        if status == 409, error.code == "request_exists", let turnID = error.turnID {
            let turn: GroupTurn = try await groupCall("/api/groups/\(groupID)/turns/\(turnID)", generation: generation)
            try checkGroupSession(generation)
            throw GroupRequestExists(turn: turn)
        }
        throw error
    }
}
