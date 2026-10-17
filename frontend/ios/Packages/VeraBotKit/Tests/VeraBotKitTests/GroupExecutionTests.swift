import Foundation
import Testing
import VeraBotCore
import VeraBotData
import VeraBotNetworking
import VeraBotPersistence

private actor GroupExecutionAPIStub: GroupChatAPI {
    nonisolated static let group = ChatGroup(id: 7, name: "G", members: [ChatGroupMember(id: 20, botID: 2, name: "B", color: "gray", detail: "")])
    private var submitted: [UUID] = []
    private var submitAttempts = 0
    private var stopAttempts = 0
    private var current = GroupTask(id: 5, groupID: 7, goal: "继续", state: .running, version: 3, ownerMemberID: 20)
    func groups() async throws -> GroupListResponse { try JSONDecoder().decode(GroupListResponse.self, from: Data(#"{"groups":[{"id":7,"name":"G","members":[]}] }"#.utf8)) }
    func createGroup(_ request: GroupCreateRequest) async throws -> ChatGroup { Self.group }
    func group(id: Int) async throws -> ChatGroup { Self.group }
    func updateGroup(id: Int, request: GroupUpdateRequest) async throws -> ChatGroup { Self.group }
    func deleteGroup(id: Int) async throws -> OKResponse { try JSONDecoder().decode(OKResponse.self, from: Data(#"{"ok":true}"#.utf8)) }
    func groupMessages(groupID: Int, beforeID: Int?) async throws -> GroupMessagesResponse { try JSONDecoder().decode(GroupMessagesResponse.self, from: Data(#"{"messages":[],"next_before_id":null}"#.utf8)) }
    func clearGroupMessages(groupID: Int) async throws -> OKResponse { try JSONDecoder().decode(OKResponse.self, from: Data(#"{"ok":true}"#.utf8)) }
    func groupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn { throw APIError(status: 404, message: "missing") }
    func stopGroupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn { throw APIError(status: 500, message: "legacy") }
    nonisolated func groupChatStream(groupID: Int, request: GroupChatRequest) -> AsyncThrowingStream<GroupChatEvent, Error> { AsyncThrowingStream { $0.finish() } }
    nonisolated func retryGroupMessage(groupID: Int, messageID: Int, requestID: UUID) -> AsyncThrowingStream<GroupChatEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func submitGroupInput(groupID: Int, request: GroupInputRequest) async throws -> GroupInputReceipt {
        submitAttempts += 1; submitted.append(request.clientRequestID)
        if submitAttempts == 1 { throw APIError(status: 0, message: "connection lost") }
        return GroupInputReceipt(task: current, inputID: 8, turnID: 11, eventCursor: 0)
    }
    func groupInputReceipt(groupID: Int, requestID: UUID) async throws -> GroupInputReceipt { throw APIError(status: 404, message: "missing") }
    func groupExecution(groupID: Int) async throws -> GroupExecutionSnapshot { GroupExecutionSnapshot(task: current, eventCursor: 0) }
    nonisolated func observeGroupExecution(groupID: Int, afterID: Int) -> AsyncThrowingStream<GroupExecutionEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func stopGroupTask(groupID: Int, taskID: Int, expectedVersion: Int, requestID: UUID) async throws -> GroupTask {
        stopAttempts += 1; current.state = .stopped; current.version += 1; return current
    }
    func resumeGroupTask(groupID: Int, taskID: Int, expectedVersion: Int, message: String, requestID: UUID) async throws -> GroupTask { current }
    func retryGroupTaskMessage(groupID: Int, messageID: Int, expectedVersion: Int, requestID: UUID) async throws -> GroupTask { current }
    func submitIDs() -> [UUID] { submitted }
    func stopCount() -> Int { stopAttempts }
}

@Test func oldGroupJSONWithoutDefaultDecodesAndPreservesDraft() throws {
    let data = Data(#"{"id":7,"name":"G","members":[],"default_bot_id":99,"read_only":true,"active_turn_id":null,"last_message":null}"#.utf8)
    let group = try JSONDecoder().decode(ChatGroup.self, from: data)
    #expect(group.id == 7)
    #expect(group.readOnly)
    let encoded = try JSONEncoder().encode(group)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("default_bot_id"))
}

@Test func sameClarifierSurvivesSnapshotReload() throws {
    let json = #"{"task":{"id":5,"group_id":7,"goal":"徒步","state":"awaiting_user","version":3,"owner_member_id":22,"root_message_id":18,"created_at":"now","updated_at":"now","finished_at":null},"clarification":{"id":9,"task_id":5,"group_id":7,"owner_member_id":22,"original_request":"帮我安排一下","missing_information":["日期"],"latest_question_message_id":20,"status":"awaiting_user","created_at":"now","updated_at":"now"},"event_cursor":41}"#
    let snapshot = try JSONDecoder().decode(GroupExecutionSnapshot.self, from: Data(json.utf8))
    let reloaded = try JSONDecoder().decode(GroupExecutionSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(reloaded.clarification?.ownerMemberID == 22)
    #expect(reloaded.clarification?.id == 9)
}

@Test func cumulativeSnapshotReplacesExistingMessageWithoutAppending() {
    let original = GroupMessage(id: 30, memberID: 22, content: "你好", status: .streaming, groupID: 7, turnID: 2)
    var state = GroupExecutionViewState(messages: [original])
    let event = GroupExecutionEvent(id: 42, groupID: 7, taskID: 5, version: 3, kind: "message_snapshot",
        payload: .object(["message_id": .number(30), "content": .string("你好，世界")]), createdAt: "now")
    #expect(GroupExecutionReducer.apply(event, to: &state, groupID: 7))
    #expect(state.messages.count == 1)
    #expect(state.messages[0].content == "你好，世界")
}

@Test func lateOldVersionOrOtherAccountEventDoesNotReplaceCurrentTask() {
    let task = GroupTask(id: 8, groupID: 7, goal: "new", state: .running, version: 4, ownerMemberID: 20,
                         rootMessageID: nil, createdAt: "now", updatedAt: "now", finishedAt: nil)
    var state = GroupExecutionViewState(snapshot: GroupExecutionSnapshot(task: task, eventCursor: 10))
    let old = GroupExecutionEvent(id: 11, groupID: 7, taskID: 7, version: 8, kind: "message_snapshot",
        payload: .object(["message_id": .number(1), "content": .string("stale")]), createdAt: "now")
    #expect(!GroupExecutionReducer.apply(old, to: &state, groupID: 7))
    let foreign = GroupExecutionEvent(id: 12, groupID: 9, taskID: 8, version: 4, kind: "message_snapshot",
        payload: .object(["message_id": .number(2), "content": .string("foreign")]), createdAt: "now")
    #expect(!GroupExecutionReducer.apply(foreign, to: &state, groupID: 7))
    #expect(state.messages.isEmpty)
}

@Test func groupInputEncodesStructuredTargetsAndNoDefaultResponder() throws {
    let input = GroupInputRequest(message: "请看看", targetMemberIDs: [20, 22], replyToMessageID: 19)
    let text = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
    #expect(text.contains("target_member_ids"))
    #expect(text.contains("reply_to_message_id"))
    #expect(!text.contains("default_bot_id"))
}

@Test func multiMentionKeepsSelectedMemberOrderAndRemovesDuplicates() {
    let input = GroupInputRequest(message: "review", targetMemberIDs: [23, 20, 23, 22])
    #expect(input.targetMemberIDs == [23, 20, 22])
}

@Test func everyoneDoesNotMixWithExplicitTargets() {
    let input = GroupInputRequest(message: "discuss", targetMemberIDs: [23, 20], everyone: true)
    #expect(input.everyone)
    #expect(input.targetMemberIDs.isEmpty)
}

@Test func createAndRenameRequestsContainNoDefaultField() throws {
    let create = String(decoding: try JSONEncoder().encode(GroupCreateRequest(name: "G", botIDs: [2, 3])), as: UTF8.self)
    let rename = String(decoding: try JSONEncoder().encode(GroupUpdateRequest(name: "G2")), as: UTF8.self)
    #expect(!create.contains("default_bot_id"))
    #expect(!rename.contains("default_bot_id"))
}

@Test func executionSnapshotAndMessagesSurviveLocalStoreReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = LocalDatabase(url: directory.appendingPathComponent("conversation.sqlite"))
    defer { database.close() }
    let store = ConversationStore(database: database)
    let task = GroupTask(id: 5, groupID: 7, goal: "安排徒步", state: .awaitingUser, version: 3, ownerMemberID: 20)
    let snapshot = GroupExecutionSnapshot(task: task, clarification: GroupClarification(id: 9, taskID: 5, groupID: 7, ownerMemberID: 20), eventCursor: 41)
    let message = GroupMessage(id: 30, memberID: 20, content: "哪一天？", groupID: 7, turnID: 2, role: .bot)
    try await store.saveGroupExecution(snapshot, messages: [message], id: \.id, status: { $0.status.rawValue }, conversationID: 7)
    let restored = try #require(await store.groupExecutionSnapshot(GroupExecutionSnapshot.self, conversationID: 7))
    let messages = try await store.messages(GroupMessage.self, kind: "group", conversationID: 7)
    #expect(restored.eventCursor == 41 && restored.clarification?.ownerMemberID == 20)
    #expect(messages.map(\.value.content) == ["哪一天？"])
}

@MainActor @Test func uncertainSubmitRetriesSameUUIDAndObserverLeaveDoesNotStopTask() async throws {
    let api = GroupExecutionAPIStub()
    let model = GroupChatViewModel(group: GroupExecutionAPIStub.group, api: api)
    model.send(text: "看看这个", targetMemberIDs: [20])
    for _ in 0..<100 { if !model.sending { break }; try await Task.sleep(for: .milliseconds(2)) }
    let ids = await api.submitIDs()
    #expect(ids.count == 2 && ids[0] == ids[1])
    #expect(model.draft.isEmpty)
    #expect(model.execution.snapshot.task?.state == .running)
    model.leave()
    #expect(await api.stopCount() == 0)
}

@MainActor @Test func explicitStopUsesTaskVersionedEndpoint() async throws {
    let api = GroupExecutionAPIStub()
    let model = GroupChatViewModel(group: GroupExecutionAPIStub.group, api: api)
    await model.load()
    await model.stop()
    #expect(await api.stopCount() == 1)
    #expect(model.execution.snapshot.task?.state == .stopped)
}

@Test @MainActor func attachmentOnlySendPreservesExistingDraft() async throws {
    let api = GroupExecutionAPIStub()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConversationStore(database: LocalDatabase(url: directory.appendingPathComponent("conversation.sqlite")))
    let repo = ConversationRepository(store: store, api: APIClient(baseURL: URL(string: "http://unused.test")!, token: nil),
                                      groupAPI: api, sessionIsCurrent: { true })
    let model = GroupChatViewModel(group: GroupExecutionAPIStub.group, api: api, repository: repo)
    model.draft = "尚未写完的消息"
    var queuedDraft: String?
    var didQueue = false
    model.send(text: "", attachmentIDs: ["att_a", "att_b"], onQueued: { accepted in
        didQueue = accepted
        queuedDraft = model.draft
    })
    #expect(model.draft == "尚未写完的消息")
    #expect(model.pendingInput?.attachmentIDs == ["att_a", "att_b"])
    for _ in 0..<100 {
        if !model.sending { break }
        try? await Task.sleep(for: .milliseconds(2))
    }
    #expect(!model.sending)
    #expect(didQueue)
    #expect(queuedDraft == "尚未写完的消息")
    #expect(try await repo.draft(kind: .group, id: model.group.id) == "尚未写完的消息")
    #expect(model.draft == "尚未写完的消息")
    model.leave()
}

@Test @MainActor func attachmentQueueFailureAllowsBatchRetry() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let api = GroupExecutionAPIStub()
    let store = ConversationStore(database: LocalDatabase(url: directory.appendingPathComponent("conversation.sqlite")))
    let repo = ConversationRepository(store: store, api: APIClient(baseURL: URL(string: "http://unused.test")!, token: nil),
                                      groupAPI: api, sessionIsCurrent: { false })
    let model = GroupChatViewModel(group: GroupExecutionAPIStub.group, api: api, repository: repo)
    var queued: Bool?
    model.send(text: "", attachmentIDs: ["att_a"], onQueued: { queued = $0 })
    for _ in 0..<100 {
        if !model.sending { break }
        try? await Task.sleep(for: .milliseconds(2))
    }
    #expect(queued == false)
    #expect(model.pendingInput == nil)
    #expect(await api.submitIDs().isEmpty)
    model.leave()
}
