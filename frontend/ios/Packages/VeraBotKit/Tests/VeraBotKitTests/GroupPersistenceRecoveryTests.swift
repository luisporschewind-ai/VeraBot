import Foundation
import Testing
import VeraBotCore
import VeraBotData
import VeraBotNetworking
import VeraBotPersistence

private actor RecoveryAPI: GroupChatAPI {
    let polls: Bool
    nonisolated let manualStream: Bool
    nonisolated let events: AsyncThrowingStream<GroupChatEvent, Error>
    private let continuation: AsyncThrowingStream<GroupChatEvent, Error>.Continuation
    var turnCalls = 0
    init(polls: Bool = false, manualStream: Bool = false) {
        self.polls = polls; self.manualStream = manualStream
        (events, continuation) = AsyncThrowingStream.makeStream()
    }
    func emit(_ event: GroupChatEvent) { continuation.yield(event) }
    func finishStream() { continuation.finish() }
    nonisolated static let group = ChatGroup(id: 7, name: "Recovery", members: [ChatGroupMember(id: 21, botID: 1, name: "A", color: "gray", detail: "")])
    nonisolated static let partial = GroupMessage(id: 101, memberID: 21, content: "partial", status: .streaming, groupID: 7, turnID: 9, role: .bot)
    nonisolated static func turn(status: String, content: String) throws -> GroupTurn {
        let body = """
        {"id":9,"group_id":7,"client_request_id":"11111111-1111-1111-1111-111111111111","mode":"single","status":"\(status)","cancel_requested":false,"messages":[{"id":101,"group_id":7,"turn_id":9,"member_id":21,"role":"bot","content":"\(content)","status":"\(status == "running" ? "streaming" : status)"}]}
        """
        return try JSONDecoder().decode(GroupTurn.self, from: Data(body.utf8))
    }
    func group(id: Int) async throws -> ChatGroup { Self.group }
    func groupMessages(groupID: Int, beforeID: Int?) async throws -> GroupMessagesResponse {
        try JSONDecoder().decode(GroupMessagesResponse.self, from: Data(#"{"messages":[{"id":101,"group_id":7,"turn_id":9,"member_id":21,"role":"bot","content":"partial","status":"streaming"}]}"#.utf8))
    }
    func syncGroupMessages(groupID: Int, beforeID: Int?, expectedRevision: Int64?) async throws -> GroupMessagesSyncResponse {
        try JSONDecoder().decode(GroupMessagesSyncResponse.self, from: Data(#"{"revision":1,"unchanged":false,"messages":[{"id":101,"group_id":7,"turn_id":9,"member_id":21,"role":"bot","content":"partial","status":"streaming"}]}"#.utf8))
    }
    func groupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn {
        turnCalls += 1
        return try Self.turn(status: polls && turnCalls == 1 ? "running" : "completed", content: polls && turnCalls == 1 ? "partial" : "complete answer")
    }
    func stopGroupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn { try Self.turn(status: "stopped", content: "stopped answer") }
    nonisolated func groupChatStream(groupID: Int, request: GroupChatRequest) -> AsyncThrowingStream<GroupChatEvent, Error> {
        if manualStream { return events }
        return AsyncThrowingStream { continuation in
            let question = GroupMessage(id: 100, memberID: nil, content: "question", groupID: 7, turnID: 9)
            continuation.yield(GroupChatEvent(groupID: 7, turnID: 9, payload: .turnStart(userMessage: question, speakerMemberIDs: [21])))
            continuation.yield(GroupChatEvent(groupID: 7, turnID: 9, payload: .messageStart(Self.partial)))
        }
    }
    nonisolated func retryGroupMessage(groupID: Int, messageID: Int, requestID: UUID) -> AsyncThrowingStream<GroupChatEvent, Error> { groupChatStream(groupID: groupID, request: GroupChatRequest(message: "retry")) }
    func groups() async throws -> GroupListResponse { throw APIError(status: 501, message: "unused") }
    func createGroup(_ request: GroupCreateRequest) async throws -> ChatGroup { throw APIError(status: 501, message: "unused") }
    func updateGroup(id: Int, request: GroupUpdateRequest) async throws -> ChatGroup { throw APIError(status: 501, message: "unused") }
    func deleteGroup(id: Int) async throws -> OKResponse { throw APIError(status: 501, message: "unused") }
    func clearGroupMessages(groupID: Int) async throws -> OKResponse { throw APIError(status: 501, message: "unused") }
}

@MainActor @Test func retiredGroupModelCannotSaveDelayedDraftAfterAccountChange() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let oldDatabase = LocalDatabase(url: directory.appendingPathComponent("old/conversation.sqlite"))
    let newDatabase = LocalDatabase(url: directory.appendingPathComponent("new/conversation.sqlite"))
    defer { oldDatabase.close(); newDatabase.close() }
    let api = RecoveryAPI()
    let oldStore = ConversationStore(database: oldDatabase)
    let newStore = ConversationStore(database: newDatabase)
    let repository = ConversationRepository(store: oldStore, api: APIClient(baseURL: URL(string: "https://example.invalid")!, token: nil), groupAPI: api, sessionIsCurrent: { true })
    let session = AuthSession(tokens: AuthTokens(access: "old", refresh: nil))
    let generation = session.generation
    let model = GroupChatViewModel(group: RecoveryAPI.group, api: api, repository: repository,
                                  sessionIsCurrent: { session.isCurrent(generation) })
    await model.saveDraft("old draft")
    #expect(try await oldStore.draft(kind: "group", conversationID: 7) == "old draft")
    session.set(AuthTokens(access: "new", refresh: nil))
    try await newStore.saveDraft("new account draft", kind: "group", conversationID: 7)
    await model.saveDraft("obsolete delayed draft")
    #expect(try await oldStore.draft(kind: "group", conversationID: 7) == "old draft")
    #expect(try await newStore.draft(kind: "group", conversationID: 7) == "new account draft")
}
