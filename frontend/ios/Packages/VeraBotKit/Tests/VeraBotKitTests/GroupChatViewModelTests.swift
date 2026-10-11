import Foundation
import Testing
import VeraBotCore
@testable import VeraBotNetworking

private actor GroupVMFixture: GroupChatAPI {
    var calls = 0
    let delayed: Bool
    let unavailable: Bool
    let recovering: Bool
    var turnCalls = 0
    init(delayed: Bool = false, unavailable: Bool = false, recovering: Bool = false) { self.delayed = delayed; self.unavailable = unavailable; self.recovering = recovering }
    nonisolated static let group = ChatGroup(id: 7, name: "伙伴", members: [ChatGroupMember(id: 21, botID: 1, name: "A", color: "gray", detail: ""), ChatGroupMember(id: 22, botID: 2, name: "B", color: "gray", detail: ""), ChatGroupMember(id: 23, botID: 3, name: "C", color: "gray", detail: "")], defaultMemberID: 21)
    nonisolated static let turnBody = #"{"id":9,"group_id":7,"client_request_id":"11111111-1111-1111-1111-111111111111","mode":"single","status":"completed","cancel_requested":false,"messages":[{"id":100,"group_id":7,"turn_id":9,"role":"user","content":"已有历史","status":"completed"}]}"#
    func group(id: Int) async throws -> ChatGroup {
        calls += 1
        if delayed { try await Task.sleep(for: .milliseconds(30)) }
        if calls > 1 { throw APIError(status: 503, message: "failed") }
        if unavailable { return ChatGroup(id: 7, name: "伙伴", members: [ChatGroupMember(id: 21, botID: nil, name: "A", color: "gray", detail: "", available: false)], defaultMemberID: 0) }
        return Self.group
    }
    func groups() async throws -> GroupListResponse { try JSONDecoder().decode(GroupListResponse.self, from: Data(#"{"groups":[]}"#.utf8)) }
    func createGroup(_ request: GroupCreateRequest) async throws -> ChatGroup { Self.group }
    func updateGroup(id: Int, request: GroupUpdateRequest) async throws -> ChatGroup {
        ChatGroup(id: id, name: request.name ?? Self.group.name, members: Self.group.members,
                  defaultMemberID: Self.group.members.first { $0.botID == request.defaultBotID }?.id ?? Self.group.defaultMemberID)
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
            if unavailable {
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
@MainActor @Test func GroupChatViewModelRejectedSendKeepsDraftAndDoesNotInventMessages() async throws {
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: GroupVMFixture())
    model.send(text: "尚未送达", mode: .single, targetBotID: 1)
    for _ in 0..<100 { if !model.busy { break }; try await Task.sleep(for: .milliseconds(1)) }
    #expect(model.draft == "尚未送达" && model.state.messages.isEmpty)
    #expect(!model.busy && model.errorMessage != nil)
}
@MainActor @Test func GroupChatViewModelIgnoresOldSessionLoad() async {
    let api = GroupVMFixture(delayed: true)
    var current = true
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: api, sessionIsCurrent: { current })
    let work = Task { await model.load() }
    while await api.calls == 0 { await Task.yield() }
    current = false; await work.value
    #expect(model.state.messages.isEmpty && model.errorMessage == nil)
}

@MainActor @Test func GroupChatViewModelRefreshesUnavailableMembersAndExplainsTurnFailure() async throws {
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: GroupVMFixture(unavailable: true))
    model.send(text: "问题", mode: .single, targetBotID: 1)
    for _ in 0..<100 { if !model.busy { break }; try await Task.sleep(for: .milliseconds(1)) }
    #expect(model.group.readOnly && !model.group.members[0].available)
    #expect(model.errorMessage == "这位伙伴已不可用。")
}

@MainActor @Test func GroupChatChangedDefaultImmediatelySelectsNewResponder() async throws {
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: GroupVMFixture())
    await model.load()
    #expect(model.preferredBotID == 1)
    try await model.update(defaultBotID: 3)
    #expect(model.group.defaultBotID == 3)
    #expect(model.preferredBotID == 3)
}
@MainActor @Test func GroupChatRenamingPreservesExplicitResponder() async throws {
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: GroupVMFixture())
    await model.load()
    model.preferredBotID = 2
    try await model.update(name: "New name")
    #expect(model.preferredBotID == 2)
}
@MainActor @Test func GroupChatSavingDefaultReplacesStaleLocalTargetEvenWhenDefaultUnchanged() async throws {
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: GroupVMFixture())
    model.preferredBotID = 2
    try await model.update(defaultBotID: 1)
    #expect(model.preferredBotID == 1)
}

@MainActor @Test func GroupChatReloadReconcilesRunningSnapshotWithoutAnotherAction() async {
    let api = GroupVMFixture(recovering: true)
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: api)
    await model.load()
    #expect(await api.turnCalls == 2)
    #expect(model.state.status == .interrupted)
    #expect(!model.busy && !model.loading)
    #expect(model.state.messages.first?.content == "已有历史")
}
@MainActor @Test func GroupChatLeaveCancelsRestoredTurnReconciliation() async {
    let api = GroupVMFixture(recovering: true)
    let model = GroupChatViewModel(group: GroupVMFixture.group, api: api)
    let work = Task { await model.load() }
    while await api.turnCalls == 0 { await Task.yield() }
    model.leave()
    await work.value
    #expect(model.state.status == .running)
    #expect(!model.loading && model.errorMessage == nil)
}
