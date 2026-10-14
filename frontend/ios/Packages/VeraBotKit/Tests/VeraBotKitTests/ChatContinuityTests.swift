import Foundation
import Testing
import VeraBotCore
import VeraBotData
import VeraBotNetworking
import VeraBotPersistence

struct ChatContinuityTests {
    @Test func durableIdentityAndSparseReadOutbox() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let db = LocalDatabase(url: url)
        let repo = ConversationActivityRepository(database: db)
        let input = ChatInputRequest(clientRequestID: "stable", message: "hello", attachmentIDs: ["attachment"], expectedGeneration: 3)
        try await repo.savePending(input, botID: 7)
        let recreated = ConversationActivityRepository(database: db)
        #expect(try await recreated.pending(botID: 7) == [input])
        try await recreated.enqueueRead(kind: "private", id: 7, generation: 3, message: MessagePublication(messageID: 32, publicationRevision: 1))
        try await recreated.enqueueRead(kind: "private", id: 7, generation: 3, message: MessagePublication(messageID: 99, publicationRevision: 2))
        #expect(try await recreated.readOutbox(kind: "private", id: 7, generation: 3).map(\.messageID) == [32, 99])
        try await recreated.enqueueRead(kind: "private", id: 7, generation: 3, message: MessagePublication(messageID: 32, publicationRevision: 2))
        #expect(try await recreated.readOutbox(kind: "private", id: 7, generation: 3).first?.publicationRevision == 2)
        try await recreated.reconcileGeneration(botID: 7, generation: 4)
        #expect(try await recreated.pending(botID: 7).isEmpty)
        #expect(try await recreated.readOutbox(kind: "private", id: 7, generation: 3).isEmpty)
        db.close()
    }
    @Test func waitingAnswersAndStopsKeepOriginalControlIdentityAcrossRecreation() async throws {
        let db = LocalDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
        let repo = ConversationActivityRepository(database: db)
        let answer = ChatControlSubmission(requestID: "answer", generation: 3, taskID: 12, version: 2, waitID: "wait:12:2", message: "this week")
        let stop = ChatControlSubmission(requestID: "stop", generation: 3, taskID: 13, version: 1)
        try await repo.saveControl(answer, botID: 7); try await repo.saveControl(stop, botID: 7)
        let recreated = ConversationActivityRepository(database: db)
        #expect(try await recreated.pendingControls(botID: 7) == [answer, stop])
        try await recreated.reconcileGeneration(botID: 7, generation: 4)
        #expect(try await recreated.pendingControls(botID: 7).isEmpty)
        db.close()
    }
    @Test func optimisticIdentityMergesWithHistoryAfterLostReceipt() async throws {
        let db = LocalDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
        let store = ConversationStore(database: db)
        let stable = UUID()
        _ = try await store.saveMessage(LocalPrivateMessage(id: stable, role: "user", content: "hello"), kind: "private", conversationID: 7, localID: stable.uuidString, remoteID: nil, sortKey: 1, status: "sending")
        let fromHistory = LocalPrivateMessage(remoteID: 31, role: "user", content: "hello")
        _ = try await store.saveMessage(fromHistory, kind: "private", conversationID: 7, localID: fromHistory.id.uuidString, remoteID: 31, sortKey: 31, status: "synced")
        let accepted = LocalPrivateMessage(id: stable, remoteID: 31, role: "user", content: "hello")
        _ = try await store.saveMessage(accepted, kind: "private", conversationID: 7, localID: stable.uuidString, remoteID: 31, sortKey: 31, status: "synced")
        let messages = try await store.messages(LocalPrivateMessage.self, kind: "private", conversationID: 7)
        #expect(messages.count == 1)
        #expect(messages.first?.localID == stable.uuidString)
        #expect(messages.first?.value.id == stable)
        db.close()
    }
    @Test func acknowledgmentKeepsNewerInFlightRevision() async throws {
        let db = LocalDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
        let repo = ConversationActivityRepository(database: db)
        let old = MessagePublication(messageID: 32, publicationRevision: 1)
        try await repo.enqueueRead(kind: "private", id: 7, generation: 1, message: old)
        try await repo.enqueueRead(kind: "private", id: 7, generation: 1, message: MessagePublication(messageID: 32, publicationRevision: 2))
        try await repo.acknowledgeReads(kind: "private", id: 7, generation: 1, messages: [old])
        #expect(try await repo.readOutbox(kind: "private", id: 7, generation: 1) == [MessagePublication(messageID: 32, publicationRevision: 2)])
        let first = ChatInputRequest(clientRequestID: "fixed", message: "first", expectedGeneration: 1)
        try await repo.savePending(first, botID: 7)
        await #expect(throws: PersistenceError.self) { try await repo.savePending(ChatInputRequest(clientRequestID: "fixed", message: "changed", expectedGeneration: 1), botID: 7) }
        db.close()
    }
    @Test func actualViewportRejectsEdgesAndAllowsLongAndShortBodies() {
        #expect(!ConversationVisibilityPolicy.isVisible(bodyHeight: 60, viewportHeight: 500, intersectionHeight: 1))
        #expect(!ConversationVisibilityPolicy.isVisible(bodyHeight: 3000, viewportHeight: 500, intersectionHeight: 10))
        #expect(ConversationVisibilityPolicy.isVisible(bodyHeight: 3000, viewportHeight: 500, intersectionHeight: 300))
        #expect(ConversationVisibilityPolicy.isVisible(bodyHeight: 16, viewportHeight: 500, intersectionHeight: 16))
    }
    @Test func parserUsesPersistentIDsAndIgnoresKeepalive() throws {
        var parser = DurableSSEParser()
        let keepalive = parser.line(": keepalive")
        #expect(keepalive == nil)
        _ = parser.line("id: 20"); _ = parser.line("event: message_updated")
        _ = parser.line(#"data: {"generation":1,"content":"replacement"}"#)
        let parsed = parser.line("")
        let event = try #require(parsed)
        #expect(event.id == 20); #expect(event.name == "message_updated")
        #expect(String(decoding: event.data, as: UTF8.self).contains("replacement"))
    }
    @Test func labelsAndVisibilityAreSessionScoped() {
        var session = ConversationReadingSession()
        session.enter([MessagePublication(messageID: 4, publicationRevision: 1)])
        session.include([MessagePublication(messageID: 5, publicationRevision: 2)])
        session.include([]) // server read acknowledgments never remove entry labels
        #expect(session.newMessageIDs == [4, 5])
        #expect(session.showsNewMessagesDivider(messageID: 4))
        #expect(!session.showsNewMessagesDivider(messageID: 5))
        var single = ConversationReadingSession()
        single.enter([MessagePublication(messageID: 9, publicationRevision: 1)])
        #expect(single.showsNewMessagesDivider(messageID: 9))
        #expect(!single.showsNewMessagesDivider(messageID: 8))
        let visible1 = !session.observe(messageID: 4, revision: 1, visibleFraction: 1, foreground: true, pageVisible: true, now: 0)
        #expect(visible1)
        let visible2 = !session.observe(messageID: 4, revision: 1, visibleFraction: 0, foreground: true, pageVisible: true, now: 0.4)
        #expect(visible2)
        let visible3 = !session.observe(messageID: 4, revision: 1, visibleFraction: 1, foreground: true, pageVisible: true, now: 1)
        #expect(visible3)
        let visible4 = session.observe(messageID: 4, revision: 1, visibleFraction: 1, foreground: true, pageVisible: true, now: 1.5)
        #expect(visible4)
        let visible5 = !session.observe(messageID: 4, revision: 2, visibleFraction: 1, foreground: false, pageVisible: true, now: 2)
        #expect(visible5)
        session.leave()
        #expect(session.newMessageIDs.isEmpty)
        #expect(ConversationActivity.unreadLabel(100) == "99+")
    }
    @Test func cursorDomainsAndCompletePartialReplacement() throws {
        let data = Data(#"{"generation":3,"cursor":100,"event_cursor":7,"tasks":[{"id":1,"bot_id":7,"generation":3,"client_request_id":"stable","state":"running","phase":"replying","version":1,"user_message_id":31,"assistant_message_id":32,"content":"replacement","traces":[],"message_status":"running","publication_revision":0}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(ChatExecutionSnapshot.self, from: data)
        #expect(snapshot.cursor == 100)
        #expect(snapshot.eventCursor == 7)
        var restored = ChatReplyProjection()
        restored.apply(snapshot)
        restored.apply(snapshot)
        #expect(restored.tasks.count == 1)
        #expect(restored.tasks.first?.assistantMessageID == 32)
        #expect(restored.tasks.first?.content == "replacement")
        restored.apply(ChatExecutionSnapshot(generation: 4, cursor: 101, eventCursor: 8, tasks: []))
        #expect(restored.tasks.isEmpty)
        restored.apply(snapshot)
        #expect(restored.generation == 4)
    }
    @Test func invalidatedScopeRejectsCallbacks() async throws {
        let db = LocalDatabase(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
        let repo = ConversationActivityRepository(database: db)
        await repo.invalidate()
        await #expect(throws: CancellationError.self) { try await repo.savePending(ChatInputRequest(message: "late", expectedGeneration: 1), botID: 7) }
        db.close()
    }
}

private final class ContinuityWireProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest) -> (Int, Data)] = [:]
    override class func canInit(with request: URLRequest) -> Bool { lock.withLock { handlers[request.url?.host ?? ""] != nil } }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let handler = Self.lock.withLock({ Self.handlers[url.host ?? ""] }) else { return }
        let (status, data) = handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension ChatContinuityTests {
    @Test func typedWireRetainsRequestPayloadAndOriginalReceiptGeneration() async throws {
        let host = "continuity-\(UUID().uuidString.lowercased()).test"
        let config = APITransport.makeConfiguration(); config.protocolClasses = [ContinuityWireProtocol.self]
        let transport = URLSession(configuration: config)
        let input = ChatInputRequest(clientRequestID: "stable-uuid", message: "hello", attachmentIDs: ["att"], expectedGeneration: 3)
        ContinuityWireProtocol.lock.withLock {
            ContinuityWireProtocol.handlers[host] = { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixed")
                #expect(request.url?.path == "/api/bots/7/chat/inputs")
                #expect(request.httpMethod == "POST")
                let actual = request.httpBody ?? request.httpBodyStream.flatMap { stream -> Data? in
                    stream.open(); defer { stream.close() }; var data = Data(); var buffer = [UInt8](repeating: 0, count: 2048)
                    while stream.hasBytesAvailable { let size = stream.read(&buffer, maxLength: buffer.count); if size <= 0 { break }; data.append(contentsOf: buffer.prefix(size)) }; return data
                }
                if let actual { #expect((try? JSONDecoder().decode(ChatInputRequest.self, from: actual)) == input) } else { Issue.record("missing frozen request body") }
                return (202, Data(#"{"generation":3,"cursor":100,"user_message_id":31,"assistant_message_id":32,"task":{"id":1,"bot_id":7,"generation":3,"client_request_id":"stable-uuid","state":"queued","phase":"queued","version":1,"user_message_id":31,"assistant_message_id":32,"content":"","traces":[],"message_status":"queued","publication_revision":0}}"#.utf8))
            }
        }
        defer { transport.invalidateAndCancel(); _ = ContinuityWireProtocol.lock.withLock { ContinuityWireProtocol.handlers.removeValue(forKey: host) } }
        let api = APIClient(baseURL: URL(string: "http://\(host)")!, token: "fixed", urlSession: transport)
        let first = try await api.submitChatInput(botID: 7, input: input)
        let replay = try await api.submitChatInput(botID: 7, input: input)
        #expect(first.assistantMessageID == replay.assistantMessageID)
        #expect(replay.generation == 3)
        #expect(replay.task.version == 1)
    }
    @Test func continuityRejectsSuccessfulResponseAfterAccountSwitch() async throws {
        let host = "continuity-switch-\(UUID().uuidString.lowercased()).test"
        let config = APITransport.makeConfiguration(); config.protocolClasses = [ContinuityWireProtocol.self]
        let transport = URLSession(configuration: config)
        let auth = AuthSession(tokens: AuthTokens(access: "first", refresh: "first-refresh"), urlSession: transport)
        ContinuityWireProtocol.lock.withLock { ContinuityWireProtocol.handlers[host] = { _ in
            auth.set(AuthTokens(access: "second", refresh: "second-refresh"))
            return (200, Data(#"{"cursor":10,"conversations":[]}"#.utf8))
        } }
        defer { transport.invalidateAndCancel(); _ = ContinuityWireProtocol.lock.withLock { ContinuityWireProtocol.handlers.removeValue(forKey: host) } }
        let api = APIClient(baseURL: URL(string: "http://\(host)")!, session: auth, urlSession: transport)
        await #expect(throws: CancellationError.self) { try await api.conversationActivity() }
    }
}
