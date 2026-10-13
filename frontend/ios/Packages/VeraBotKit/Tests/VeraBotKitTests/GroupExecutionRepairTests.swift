import Foundation
import Testing
import VeraBotCore
import VeraBotData
import VeraBotNetworking
import VeraBotPersistence

private actor RepairGroupAPI: GroupChatAPI {
    nonisolated static let group = ChatGroup(id: 7, name: "G", members: [.init(id: 20, botID: 2, name: "B", color: "gray", detail: "")])
    var current = GroupTask(id: 5, groupID: 7, goal: "目标", state: .awaitingUser, version: 3, ownerMemberID: 20)
    var clarification: GroupClarification? = .init(id: 9, taskID: 5, groupID: 7, ownerMemberID: 20)
    var submitted: [GroupInputRequest] = []
    var lookups: [UUID] = []
    var networkWorks = false
    var conflict = false
    var stopCalls = 0
    var cleared = false
    var emitRemoteClear = false
    var oldFailedMessage = false
    var retryVersion: Int?
    func groups() async throws -> GroupListResponse { try JSONDecoder().decode(GroupListResponse.self, from: Data(#"{"groups":[]}"#.utf8)) }
    func createGroup(_ request: GroupCreateRequest) async throws -> ChatGroup { Self.group }
    func group(id: Int) async throws -> ChatGroup { Self.group }
    func updateGroup(id: Int, request: GroupUpdateRequest) async throws -> ChatGroup { Self.group }
    func deleteGroup(id: Int) async throws -> OKResponse { try JSONDecoder().decode(OKResponse.self, from: Data(#"{"ok":true}"#.utf8)) }
    func groupMessages(groupID: Int, beforeID: Int?) async throws -> GroupMessagesResponse {
        let json = oldFailedMessage ? #"{"messages":[{"id":29,"group_id":7,"turn_id":1,"member_id":20,"role":"bot","content":"失败","status":"failed","task_id":2,"task_version":7,"attachments":[]}],"next_before_id":null}"# : #"{"messages":[],"next_before_id":null}"#
        return try JSONDecoder().decode(GroupMessagesResponse.self,from:Data(json.utf8))
    }
    func syncGroupMessages(groupID: Int, beforeID: Int?, expectedRevision: Int64?) async throws -> GroupMessagesSyncResponse { try JSONDecoder().decode(GroupMessagesSyncResponse.self, from: Data(#"{"revision":1,"messages":[],"next_before_id":null,"unchanged":false}"#.utf8)) }
    func clearGroupMessages(groupID: Int) async throws -> OKResponse { cleared = true; clarification = nil; current.state = .stopped; return try await deleteGroup(id: groupID) }
    func groupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn { throw APIError(status:404,message:"missing") }
    func stopGroupTurn(groupID: Int, turnID: Int) async throws -> GroupTurn { throw APIError(status:500,message:"legacy") }
    nonisolated func groupChatStream(groupID: Int, request: GroupChatRequest) -> AsyncThrowingStream<GroupChatEvent,Error> { AsyncThrowingStream { $0.finish() } }
    nonisolated func retryGroupMessage(groupID: Int, messageID: Int, requestID: UUID) -> AsyncThrowingStream<GroupChatEvent,Error> { AsyncThrowingStream { $0.finish() } }
    func submitGroupInput(groupID: Int, request: GroupInputRequest) async throws -> GroupInputReceipt {
        submitted.append(request)
        if conflict { current.version = 4; current.state = .running; throw APIError(status:409,message:"task_version_changed") }
        if !networkWorks { throw APIError(status:0,message:"lost response") }
        current.state = .running; clarification = nil
        return .init(task: current, inputID:8,turnID:11,eventCursor:0)
    }
    func groupInputReceipt(groupID:Int,requestID:UUID) async throws -> GroupInputReceipt {
        lookups.append(requestID)
        if conflict {throw APIError(status:404,message:"missing")}
        if !networkWorks { throw APIError(status:0,message:"offline") }
        if let last = submitted.first(where: {$0.clientRequestID == requestID}) {
            _ = last; return .init(task:current,inputID:8,turnID:11,eventCursor:0)
        }
        throw APIError(status:404,message:"missing")
    }
    func groupExecution(groupID:Int) async throws -> GroupExecutionSnapshot { .init(task: cleared ? nil : current, clarification:clarification,eventCursor:0) }
    func remoteClear() {emitRemoteClear = true}
    func takeRemoteClear() -> Bool {
        guard emitRemoteClear else {return false}
        emitRemoteClear = false;cleared = true;return true
    }
    nonisolated func observeGroupExecution(groupID:Int,afterID:Int) -> AsyncThrowingStream<GroupExecutionEvent,Error> {
        AsyncThrowingStream {continuation in
            let task = Task {
                if await takeRemoteClear() {
                    let message = GroupMessage(id:30,memberID:20,content:"将被清空",status:.completed,groupID:7,turnID:11,role:.bot)
                    let value = try! JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(message))
                    continuation.yield(.init(id:1,groupID:7,taskID:5,version:3,kind:"message_done",payload:.object(["message":value]),createdAt:"now"))
                    continuation.yield(.init(id:2,groupID:7,taskID:nil,version:0,kind:"group_cleared",payload:.object([:]),createdAt:"now"))
                }
                continuation.finish()
            }
            continuation.onTermination = {_ in task.cancel()}
        }
    }
    func stopGroupTask(groupID:Int,taskID:Int,expectedVersion:Int,requestID:UUID) async throws -> GroupTask { stopCalls += 1; current.state = .stopped; clarification = nil; return current }
    func resumeGroupTask(groupID:Int,taskID:Int,expectedVersion:Int,message:String,requestID:UUID) async throws -> GroupTask { current.state = .running;return current }
    func retryGroupTaskMessage(groupID:Int,messageID:Int,expectedVersion:Int,requestID:UUID) async throws -> GroupTask {retryVersion = expectedVersion;return current}
    func setOldFailure() {oldFailedMessage = true;current.state = .completed}
    func requestedRetryVersion() -> Int? {retryVersion}
    func setNetwork() {networkWorks = true}
    func setConflict() {conflict = true}
    func ids() -> [UUID] {submitted.map(\.clientRequestID)}
    func attempts() -> Int {submitted.count}
    func stops() -> Int {stopCalls}
    func lookupIDs() -> [UUID] {lookups}
}

@MainActor private func finishSend(_ model: GroupChatViewModel) async throws {
    for _ in 0..<100 {if !model.sending {return};try await Task.sleep(for:.milliseconds(5))}
    Issue.record("send did not finish")
}

@Test @MainActor func repairPendingRequestSurvivesLeaveAndModelRecreation() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("conversation.sqlite")
    let store = ConversationStore(database:LocalDatabase(url:url))
    let api = RepairGroupAPI()
    let privateAPI = APIClient(baseURL: URL(string:"http://unused.test")!, token:nil)
    let repo = ConversationRepository(store:store,api:privateAPI,groupAPI:api,sessionIsCurrent:{true})
    let first = GroupChatViewModel(group:RepairGroupAPI.group,api:api,repository:repo)
    first.send(text:"处理这件事")
    try await finishSend(first)
    let originalIDs = await api.ids()
    first.leave()
    await api.setNetwork()
    let second = GroupChatViewModel(group:RepairGroupAPI.group,api:api,repository:repo)
    await second.load()
    try await finishSend(second)
    #expect(second.draft.isEmpty)
    #expect(await api.lookupIDs().count >= 2)
    let ids = await api.ids()
    #expect(Set(ids).count == 1 && ids.first == originalIDs.first)
}

@Test @MainActor func repairConflictSynchronizesWithoutResending() async throws {
    let api = RepairGroupAPI();await api.setConflict()
    let model = GroupChatViewModel(group:RepairGroupAPI.group,api:api)
    defer {model.leave()}
    await model.load();model.send(text:"回答")
    try await finishSend(model)
    #expect(await api.attempts() == 1)
    #expect(model.execution.snapshot.task?.version == 4)
}

@Test @MainActor func repairClearReleasesClarificationAndAllowsNewInput() async throws {
    let api = RepairGroupAPI();await api.setNetwork()
    let model = GroupChatViewModel(group:RepairGroupAPI.group,api:api)
    defer {model.leave()}
    await model.load();try await model.clear()
    #expect(model.execution.snapshot.task == nil)
    #expect(model.execution.snapshot.clarification == nil)
    model.send(text:"新请求");try await finishSend(model)
    #expect(model.errorMessage == nil)
}

@Test @MainActor func repairWaitingClarificationCanBeStopped() async throws {
    let api = RepairGroupAPI();let model = GroupChatViewModel(group:RepairGroupAPI.group,api:api)
    await model.load();await model.stop()
    #expect(await api.stops() == 1)
    #expect(model.execution.snapshot.task?.state == .stopped)
}

@Test func repairReducerAppliesLiveIdentityAndTaskState() throws {
    var state = GroupExecutionViewState()
    let json = #"{"id":1,"group_id":7,"task_id":5,"version":1,"kind":"task_updated","payload":{"task":{"id":5,"group_id":7,"goal":"目标","state":"running","version":1,"created_at":"now","updated_at":"now"}},"created_at":"now"}"#
    let decoder=JSONDecoder()
    _ = GroupExecutionReducer.apply(try decoder.decode(GroupExecutionEvent.self,from:Data(json.utf8)),to:&state,groupID:7)
    #expect(state.snapshot.task?.state == .running)
    let message = #"{"id":2,"group_id":7,"task_id":5,"version":1,"kind":"message_start","payload":{"message":{"id":30,"group_id":7,"turn_id":11,"member_id":20,"role":"bot","content":"正在回复","status":"streaming","sender_name":"B","attachments":[]}},"created_at":"now"}"#
    _ = GroupExecutionReducer.apply(try decoder.decode(GroupExecutionEvent.self,from:Data(message.utf8)),to:&state,groupID:7)
    #expect(state.messages.first?.memberID == 20)
    #expect(state.messages.first?.senderName == "B")
}

private final class RepairLiveProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "live-repair.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"text/event-stream"])!,cacheStoragePolicy:.notAllowed)
        let event = "data: {\"id\":1,\"group_id\":7,\"task_id\":5,\"version\":1,\"kind\":\"message_snapshot\",\"payload\":{\"message_id\":30,\"content\":\"已收到\"},\"created_at\":\"now\"}\n\n"
        client?.urlProtocol(self,didLoad:Data(event.utf8))
        DispatchQueue.global().asyncAfter(deadline:.now()+2) { [self] in
            if !lock.withLock({cancelled}) {client?.urlProtocolDidFinishLoading(self)}
        }
    }
    override func stopLoading() {lock.withLock {cancelled = true}}
}

@Test func repairNetworkYieldsBeforeSSEConnectionEnds() async throws {
    let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [RepairLiveProtocol.self]
    let transport = URLSession(configuration:config);defer {transport.invalidateAndCancel()}
    let api = APIClient(baseURL:URL(string:"http://live-repair.test")!,token:nil,urlSession:transport)
    var stream = api.observeGroupExecution(groupID:7,afterID:0).makeAsyncIterator()
    let started = Date()
    let event = try await stream.next()
    #expect(event?.id == 1)
    #expect(Date().timeIntervalSince(started) < 1, "first frame must be yielded before delayed EOF")
}

@Test @MainActor func repairRemoteClearDeletesPersistentMessages() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ConversationStore(database:LocalDatabase(url:directory.appendingPathComponent("conversation.sqlite")))
    let api = RepairGroupAPI();await api.remoteClear()
    let repo = ConversationRepository(store:store,api:APIClient(baseURL:URL(string:"http://unused.test")!,token:nil),groupAPI:api,sessionIsCurrent:{true})
    let model = GroupChatViewModel(group:RepairGroupAPI.group,api:api,repository:repo)
    defer {model.leave()}
    await model.load()
    for _ in 0..<100 {if model.execution.snapshot.eventCursor == 2 {break};try await Task.sleep(for:.milliseconds(5))}
    #expect(model.state.messages.isEmpty)
    let local = try await repo.groupMessages(groupID:7)
    #expect(local.isEmpty,"remote clear must remove SQLite rows, not just upsert an empty snapshot")
}

@Test @MainActor func repairReceiptDoesNotEraseNewlyEditedDraft() async throws {
    let api=RepairGroupAPI();let model=GroupChatViewModel(group:RepairGroupAPI.group,api:api)
    defer {model.leave()}
    model.send(text:"上一条消息");try await finishSend(model)
    model.draft="下一条正在编辑"
    await api.setNetwork();model.recoverPendingSubmission();try await finishSend(model)
    #expect(model.draft == "下一条正在编辑")
}

@Test @MainActor func repairRetryHistoricalMessageUsesItsOwnTaskVersion() async throws {
    let api=RepairGroupAPI();await api.setOldFailure()
    let model=GroupChatViewModel(group:RepairGroupAPI.group,api:api)
    defer {model.leave()}
    await model.load();model.retry(messageID:29);try await finishSend(model)
    #expect(await api.requestedRetryVersion() == 7)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["VERABOT_GROUP_REPAIR_SOCKET"] == "1"))
func repairLocalBackendStreamsIdentityBeforeCompletion() async throws {
    let base=URL(string:"http://127.0.0.1:8093")!
    var login=URLRequest(url:base.appendingPathComponent("api/auth/login"));login.httpMethod="POST"
    login.setValue("application/json",forHTTPHeaderField:"Content-Type")
    login.httpBody=Data(#"{"username":"group-demo","password":"group-demo-123"}"#.utf8)
    let (data,response)=try await URLSession.shared.data(for:login)
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
    let object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
    let token=try #require(object["token"] as? String)
    let api=APIClient(baseURL:base,token:token)
    let bots=try await api.bots()
    let group=try await api.createGroup(.init(name:"Swift socket 修复联调",botIDs:Array(bots.bots.prefix(2).map(\.id))))
    let member=try #require(group.members.first)
    let receipt=try await api.submitGroupInput(groupID:group.id,request:.init(message:"稳定实时输出 [stream-probe]",targetMemberIDs:[member.id]))
    var firstLive=false
    var finalSeen=false
    for try await event in api.observeGroupExecution(groupID:group.id,afterID:receipt.eventCursor) {
        #expect(event.groupID == group.id)
        if event.kind == "message_snapshot", !firstLive {
            let snapshot=try await api.groupExecution(groupID:group.id)
            #expect(snapshot.task?.state == .running,"real backend frame must arrive while provider is still generating")
            firstLive=true
        }
        if event.kind == "message_done", case .object(let payload)=event.payload, let value=payload["message"] {
            let message=try JSONDecoder().decode(GroupMessage.self,from:JSONEncoder().encode(value))
            if message.role == .bot {
                #expect(message.memberID == member.id)
                #expect(message.taskID == receipt.task.id)
                #expect(!message.content.isEmpty && message.status == .completed)
                finalSeen=true
            }
        }
    }
    #expect(firstLive && finalSeen)
    _ = try await api.deleteGroup(id:group.id)
}
