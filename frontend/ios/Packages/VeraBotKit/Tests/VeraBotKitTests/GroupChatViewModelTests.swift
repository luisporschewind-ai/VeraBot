import Foundation
import Testing
import VeraBotCore
import VeraBotData
import VeraBotPersistence
@testable import VeraBotNetworking

private actor GroupVMFixture: GroupChatAPI {
    var calls = 0
    let delayed: Bool
    let unavailable: Bool
    let recovering: Bool
    let memberFailure: Bool
    let removeFails: Bool
    /// Fail the Nth `addGroupMember` call (1-based); `nil` never fails adds.
    let failAddOnCall: Int?
    var addCalls = 0
    var turnCalls = 0
    var members: [ChatGroupMember]
    private var pendingLoad: CheckedContinuation<Void, Never>?
    init(delayed: Bool = false, unavailable: Bool = false, recovering: Bool = false, memberFailure: Bool = false,
         removeFails: Bool = false, failAddOnCall: Int? = nil) {
        self.delayed = delayed; self.unavailable = unavailable; self.recovering = recovering; self.memberFailure = memberFailure
        self.removeFails = removeFails
        self.failAddOnCall = failAddOnCall
        self.members = Self.group.members
    }
    nonisolated static let group = ChatGroup(id: 7, name: "伙伴", members: [ChatGroupMember(id: 21, botID: 1, name: "A", color: "gray", detail: ""), ChatGroupMember(id: 22, botID: 2, name: "B", color: "gray", detail: ""), ChatGroupMember(id: 23, botID: 3, name: "C", color: "gray", detail: "")])
    nonisolated static let turnBody = #"{"id":9,"group_id":7,"client_request_id":"11111111-1111-1111-1111-111111111111","mode":"single","status":"completed","cancel_requested":false,"messages":[{"id":100,"group_id":7,"turn_id":9,"role":"user","content":"已有历史","status":"completed"}]}"#
    func group(id: Int) async throws -> ChatGroup {
        calls += 1
        if delayed { await withCheckedContinuation { pendingLoad = $0 } }
        if calls > 1 { throw APIError(status: 503, message: "failed") }
        if unavailable { return ChatGroup(id: 7, name: "伙伴", members: [ChatGroupMember(id: 21, botID: nil, name: "A", color: "gray", detail: "", available: false)]) }
        return Self.group
    }
    func resumeLoad() { pendingLoad?.resume(); pendingLoad = nil }
    func groups() async throws -> GroupListResponse { try JSONDecoder().decode(GroupListResponse.self, from: Data(#"{"groups":[]}"#.utf8)) }
    func createGroup(_ request: GroupCreateRequest) async throws -> ChatGroup { Self.group }
    func updateGroup(id: Int, request: GroupUpdateRequest) async throws -> ChatGroup {
        ChatGroup(id: id, name: request.name ?? Self.group.name, members: members)
    }
    func addGroupMember(groupID: Int, botID: Int) async throws -> ChatGroup {
        addCalls += 1
        if let failAddOnCall, addCalls == failAddOnCall {
            throw APIError(status: 500, message: "add failed")
        }
        members.append(ChatGroupMember(id: 100 + botID, botID: botID, name: "N\(botID)", color: "gray", detail: ""))
        return ChatGroup(id: groupID, name: Self.group.name, members: members)
    }
    func removeGroupMember(groupID: Int, memberID: Int) async throws -> ChatGroup {
        if removeFails { throw APIError(status: 500, message: "remove failed") }
        members.removeAll { $0.id == memberID }
        return ChatGroup(id: groupID, name: Self.group.name, members: members)
    }
    func deleteGroup(id: Int) async throws -> OKResponse { try JSONDecoder().decode(OKResponse.self, from: Data(#"{"ok":true}"#.utf8)) }
    func clearGroupMessages(groupID: Int) async throws -> OKResponse { try JSONDecoder().decode(OKResponse.self, from: Data(#"{"ok":true}"#.utf8)) }
    func groupMessages(groupID: Int, beforeID: Int?) async throws -> GroupMessagesResponse {
        try JSONDecoder().decode(GroupMessagesResponse.self, from: Data(#"{"messages":[{"id":100,"group_id":7,"turn_id":9,"role":"user","content":"已有历史","status":"completed"}],"next_before_id":null}"#.utf8))
    }
    func groupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn {
        turnCalls += 1
        let status = recovering ? (turnCalls == 1 ? "running" : "interrupted") : "completed"
        let body = Self.turnBody.replacingOccurrences(of: #""status":"completed","cancel_requested""#, with: "\"status\":\"\(status)\",\"cancel_requested\"")
        return try JSONDecoder().decode(GroupTurn.self, from: Data(body.utf8))
    }
    func stopGroupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn { try await groupTurn(groupID: groupID, turnID: turnID) }
    nonisolated func groupChatStream(groupID: Int, request: GroupChatRequest) -> AsyncThrowingStream<GroupChatEvent, Error> {
        AsyncThrowingStream { continuation in
            if memberFailure {
                let question = GroupMessage(id: 110, memberID: nil, content: "hello", groupID: 7, turnID: 10)
                let reply = GroupMessage(id: 111, memberID: 21, content: "", status: .failed,
                                         groupID: 7, turnID: 10, role: .bot)
                continuation.yield(GroupChatEvent(groupID: 7, turnID: 10,
                    payload: .turnStart(userMessage: question, speakerMemberIDs: [21])))
                continuation.yield(GroupChatEvent(groupID: 7, turnID: 10, payload: .messageDone(reply)))
                continuation.yield(GroupChatEvent(groupID: 7, turnID: 10,
                    payload: .error(code: "member_failed", message: "伙伴暂时没能回应", messageID: 111)))
                continuation.yield(GroupChatEvent(groupID: 7, turnID: 10,
                    payload: .turnDone(status: .partial, usage: nil, messageIDs: [110, 111])))
                continuation.finish()
            } else if unavailable {
                let question = GroupMessage(id: 100, memberID: nil, content: "问题", groupID: 7, turnID: 10)
                continuation.yield(GroupChatEvent(groupID: 7, turnID: 10, payload: .turnStart(userMessage: question, speakerMemberIDs: [21])))
                continuation.yield(GroupChatEvent(groupID: 7, turnID: 10, payload: .error(code: "member_unavailable", message: "这位伙伴已不可用。", messageID: nil)))
                continuation.yield(GroupChatEvent(groupID: 7, turnID: 10, payload: .turnDone(status: .partial, usage: nil, messageIDs: [100])))
                continuation.finish()
            } else { continuation.finish(throwing: APIError(status: 503, message: "failed")) }
        }
    }
    nonisolated func retryGroupMessage(groupID: Int, messageID: Int, requestID: UUID) -> AsyncThrowingStream<GroupChatEvent, Error> {
        groupChatStream(groupID: groupID, request: GroupChatRequest(message: "retry"))
    }
}

@MainActor @Test func GroupChatViewModelPreservesHistoryOnReloadFailure() async {
    let api = GroupVMFixture(); let model = GroupChatViewModel(group: GroupVMFixture.group, api: api)
    await model.load(); #expect(model.state.messages.first?.content == "已有历史")
    await model.load(); #expect(model.state.messages.first?.content == "已有历史")
    #expect(model.errorMessage != nil)
}
@MainActor @Test func GroupChatViewModelIgnoresOldSessionLoad() async {
    let api = GroupVMFixture(delayed: true)
    var current = true
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: api, sessionIsCurrent: { current })
    let work = Task { await model.load() }
    while await api.calls == 0 { await Task.yield() }
    current = false; await api.resumeLoad(); await work.value
    #expect(model.state.messages.isEmpty && model.errorMessage == nil)
}

@MainActor @Test func GroupChatViewModelAddsAndRemovesMembers() async throws {
    let api = GroupVMFixture()
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: api)
    let added = try await model.addMember(botID: 9)
    #expect(!model.group.members.contains { $0.botID == 9 })
    model.applyGroup(added)
    #expect(model.group.members.contains { $0.botID == 9 })
    let removable = try #require(model.group.members.first { $0.botID == 9 })
    let beforeCount = model.group.members.count
    let updated = try await model.removeMember(memberID: removable.id)
    // 确认前/应用前本地列表不变，避免左滑即删。
    #expect(model.group.members.count == beforeCount)
    #expect(model.group.members.contains { $0.id == removable.id })
    model.applyGroup(updated)
    #expect(!model.group.members.contains { $0.id == removable.id })
}

@MainActor @Test func GroupChatViewModelAddMembersPartialFailureKeepsSuccesses() async {
    let api = GroupVMFixture(failAddOnCall: 2)
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: api)
    let before = model.group.members.count
    let result = await model.addMembers(botIDs: [9, 10, 11])
    #expect(result.addedCount == 1)
    #expect(result.failure != nil)
    #expect(model.group.members.count == before)
    model.applyGroup(result.group)
    #expect(model.group.members.contains { $0.botID == 9 })
    #expect(!model.group.members.contains { $0.botID == 10 })
}

@MainActor @Test func GroupChatViewModelRemoveMemberFailureKeepsMembers() async throws {
    let api = GroupVMFixture(removeFails: true)
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: api)
    let before = model.group.members
    do {
        _ = try await model.removeMember(memberID: before[0].id)
        Issue.record("expected remove to fail")
    } catch {
        #expect(model.group.members.map(\.id) == before.map(\.id))
    }
}

@MainActor @Test func cachedGroupHistoryCanPageWhileServerIsUnavailable() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let database = LocalDatabase(url: directory.appendingPathComponent("conversation.sqlite"))
    defer { database.close(); try? FileManager.default.removeItem(at: directory) }
    let api = GroupVMFixture(delayed: true)
    let store = ConversationStore(database: database)
    let unusedPrivateAPI = APIClient(baseURL: URL(string: "http://unused.test")!, token: "fixture")
    let repository = ConversationRepository(store: store, api: unusedPrivateAPI, groupAPI: api, sessionIsCurrent: { true })
    for id in 1...105 {
        try await repository.saveGroupMessage(GroupMessage(id: id, memberID: 21, content: "local \(id)", groupID: 7, turnID: 9, role: .bot), groupID: 7, status: "completed")
    }
    try await repository.saveDraft("offline draft", kind: .group, id: 7)
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: api, repository: repository)
    var localReadyCalled = false
    let load = Task {
        await model.load {
            #expect(await api.calls == 0)
            #expect(model.state.messages.count == 100)
            #expect(model.draft == "offline draft")
            localReadyCalled = true
        }
    }
    // The server holds the request open; local reading must remain usable.
    for _ in 0..<1000 {
        if await api.calls > 0 { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(localReadyCalled)
    #expect(await api.calls == 1)
    #expect(model.state.messages.count == 100)
    #expect(model.draft == "offline draft")
    await model.loadOlder()
    #expect(model.state.messages.count == 105)
    #expect(model.state.messages.first?.content == "local 1")
    await api.resumeLoad()
    await load.value
    model.leave()
}
