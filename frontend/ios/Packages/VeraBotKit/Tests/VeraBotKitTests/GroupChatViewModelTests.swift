import Foundation
import Testing
import VeraBotCore
import VeraBotData
@testable import VeraBotNetworking

private actor GroupVMFixture: GroupChatAPI {
    var calls = 0
    let delayed: Bool
    let unavailable: Bool
    let recovering: Bool
    let memberFailure: Bool
    var turnCalls = 0
    var members: [ChatGroupMember]
    private var pendingLoad: CheckedContinuation<Void, Never>?
    init(delayed: Bool = false, unavailable: Bool = false, recovering: Bool = false, memberFailure: Bool = false) {
        self.delayed = delayed; self.unavailable = unavailable; self.recovering = recovering; self.memberFailure = memberFailure
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
        members.append(ChatGroupMember(id: 100 + botID, botID: botID, name: "N\(botID)", color: "gray", detail: ""))
        return ChatGroup(id: groupID, name: Self.group.name, members: members)
    }
    func removeGroupMember(groupID: Int, memberID: Int) async throws -> ChatGroup {
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
    try await model.addMember(botID: 9)
    #expect(model.group.members.contains { $0.botID == 9 })
    let removable = try #require(model.group.members.first { $0.botID == 9 })
    try await model.removeMember(memberID: removable.id)
    #expect(!model.group.members.contains { $0.botID == 9 })
}
