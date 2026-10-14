import Foundation
import Testing
import VeraBotCore
import VeraBotData
import VeraBotNetworking
import VeraBotPersistence

private actor RepositoryGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

/// Only the network is controlled; repository, decoding, staging and SQLite commits are real.
private actor RepositorySyncServer {
    let heldPageArrived = RepositoryGate()
    let releaseHeldPage = RepositoryGate()
    private let holdSecondPage: Bool
    private var failSecondPageOnce: Bool
    private var held = false
    private(set) var requests = 0

    init(holdSecondPage: Bool = false, failSecondPageOnce: Bool = false) {
        self.holdSecondPage = holdSecondPage
        self.failSecondPageOnce = failSecondPageOnce
    }

    func response(for url: URL) async -> (Int, Data) {
        requests += 1
        let secondPage = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "before_id" } == true
        if secondPage && holdSecondPage && !held {
            held = true
            await heldPageArrived.open()
            await releaseHeldPage.wait()
        }
        if secondPage && failSecondPageOnce {
            failSecondPageOnce = false
            return (503, Data(#"{"detail":"offline"}"#.utf8))
        }
        let id = secondPage ? 1 : 2
        let cursor = secondPage ? "null" : "2"
        let message = url.path.contains("/groups/")
            ? "{\"id\":\(id),\"group_id\":3,\"turn_id\":1,\"role\":\"user\",\"content\":\"page \(id)\",\"status\":\"completed\",\"attachments\":[]}"
            : "{\"id\":\(id),\"role\":\"user\",\"content\":\"page \(id)\",\"created_at\":\"now\",\"traces\":[]}"
        return (200, Data("{\"revision\":7,\"messages\":[\(message)],\"next_before_id\":\(cursor),\"unchanged\":false}".utf8))
    }
}

private final class RepositorySyncProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: RepositorySyncServer] = [:]
    static func register(_ server: RepositorySyncServer, host: String) { lock.withLock { servers[host] = server } }
    static func unregister(host: String) { _ = lock.withLock { servers.removeValue(forKey: host) } }
    override class func canInit(with request: URLRequest) -> Bool {
        lock.withLock { request.url?.host.flatMap { servers[$0] } != nil }
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let server = Self.lock.withLock({ Self.servers[url.host ?? ""] }) else { return }
        Task { @Sendable [self] in
            let (status, data) = await server.response(for: url)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private final class RepositoryFixture: @unchecked Sendable {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let host = "repository-\(UUID().uuidString.lowercased()).test"
    let database: LocalDatabase
    let store: ConversationStore
    let transport: URLSession
    let repository: ConversationRepository
    init(server: RepositorySyncServer = RepositorySyncServer(), current: @escaping @Sendable () -> Bool = { true }) {
        database = LocalDatabase(url: directory.appendingPathComponent("conversation.sqlite"))
        store = ConversationStore(database: database)
        RepositorySyncProtocol.register(server, host: host)
        let config = APITransport.makeConfiguration()
        config.protocolClasses = [RepositorySyncProtocol.self]
        transport = URLSession(configuration: config)
        let api = APIClient(baseURL: URL(string: "http://\(host)")!, token: "fixture", urlSession: transport)
        repository = ConversationRepository(store: store, api: api, groupAPI: api, sessionIsCurrent: current)
    }
    deinit {
        transport.invalidateAndCancel()
        RepositorySyncProtocol.unregister(host: host)
        database.close()
        try? FileManager.default.removeItem(at: directory)
    }
}

private func sync(_ repository: ConversationRepository, kind: ConversationKind) async throws {
    switch kind {
    case .privateChat: try await repository.syncPrivate(botID: 3)
    case .group: try await repository.syncGroup(groupID: 3)
    }
}

@Test(arguments: [ConversationKind.privateChat, .group])
func concurrentConversationSyncKeepsEveryPage(kind: ConversationKind) async throws {
    let server = RepositorySyncServer(holdSecondPage: true)
    let fixture = RepositoryFixture(server: server)
    let first = Task { try await sync(fixture.repository, kind: kind) }
    await server.heldPageArrived.wait()
    let second = Task {
        try await sync(fixture.repository, kind: kind)
        // On the broken implementation the competing sync commits and clears
        // staging before the first response is released, reproducing lost history.
        await server.releaseHeldPage.open()
    }
    // A single-flight implementation cannot finish the second caller until the
    // first caller is released. The bounded watchdog releases that valid case.
    let watchdog = Task {
        try? await Task.sleep(for: .milliseconds(300))
        await server.releaseHeldPage.open()
    }
    defer { watchdog.cancel() }
    try await first.value
    try await second.value
    switch kind {
    case .privateChat:
        let messages = try await fixture.repository.privateMessages(botID: 3)
        #expect(messages.map(\.remoteID) == [1, 2])
    case .group:
        let messages = try await fixture.repository.groupMessages(groupID: 3)
        #expect(messages.map(\.remoteID) == [1, 2])
    }
    #expect(try await fixture.repository.isHistoryComplete(kind: kind, id: 3))
    #expect(await server.requests == 2)
}

@Test func failedSyncCanResumeStagedPages() async throws {
    let server = RepositorySyncServer(failSecondPageOnce: true)
    let fixture = RepositoryFixture(server: server)
    do {
        try await fixture.repository.syncPrivate(botID: 3)
        Issue.record("Expected the first sync to fail while fetching its second page")
    } catch let error as APIError { #expect(error.status == 503) }
    #expect(try await !fixture.repository.isHistoryComplete(kind: .privateChat, id: 3))
    try await fixture.repository.syncPrivate(botID: 3)
    let messages = try await fixture.repository.privateMessages(botID: 3)
    #expect(messages.map(\.remoteID) == [1, 2])
    #expect(await server.requests == 3)
}

@Test func invalidatingDuringSyncDoesNotPublishPartialHistory() async throws {
    let server = RepositorySyncServer(holdSecondPage: true)
    let fixture = RepositoryFixture(server: server)
    let pending = Task { try await fixture.repository.syncPrivate(botID: 3) }
    await server.heldPageArrived.wait()
    await fixture.repository.invalidate()
    await server.releaseHeldPage.open()
    do {
        try await pending.value
        Issue.record("Invalidated sync completed successfully")
    } catch is CancellationError {}
    let messages = try await fixture.repository.privateMessages(botID: 3)
    #expect(messages.isEmpty)
    #expect(try await !fixture.repository.isHistoryComplete(kind: .privateChat, id: 3))
}

@Test func privateAndGroupSyncWithSameIDProgressIndependently() async throws {
    let server = RepositorySyncServer(holdSecondPage: true)
    let fixture = RepositoryFixture(server: server)
    let pending = Task { try await fixture.repository.syncPrivate(botID: 3) }
    await server.heldPageArrived.wait()
    try await fixture.repository.syncGroup(groupID: 3)
    let groups = try await fixture.repository.groupMessages(groupID: 3)
    #expect(groups.map(\.remoteID) == [1, 2])
    await server.releaseHeldPage.open()
    try await pending.value
    let privateMessages = try await fixture.repository.privateMessages(botID: 3)
    #expect(privateMessages.map(\.remoteID) == [1, 2])
}

@Test(arguments: [false, true])
func staleRepositoriesRejectAllLocalWrites(explicitInvalidation: Bool) async throws {
    let fixture = RepositoryFixture(current: { explicitInvalidation })
    let privateMessage = LocalPrivateMessage(try JSONDecoder().decode(ChatMessage.self, from: Data(#"{"id":17,"role":"user","content":"keep","created_at":"now","traces":[]}"#.utf8)))
    let groupMessage = GroupMessage(id: 17, memberID: nil, content: "keep", groupID: 3)
    _ = try await fixture.store.saveMessage(privateMessage, kind: "private", conversationID: 3, localID: privateMessage.id.uuidString, remoteID: 17, sortKey: 17, status: "synced")
    _ = try await fixture.store.saveMessage(groupMessage, kind: "group", conversationID: 3, remoteID: 17, sortKey: 17, status: "synced")
    try await fixture.store.saveDraft("keep", kind: "private", conversationID: 3)
    let group = ChatGroup(id: 3, name: "keep", members: [])
    try await fixture.store.saveConversation(group, kind: "group", id: 3)
    if explicitInvalidation { await fixture.repository.invalidate() }
    let writes: [@Sendable () async throws -> Void] = [
        { try await fixture.repository.savePrivate(privateMessage, botID: 3, sortKey: 999, status: "changed") },
        { try await fixture.repository.deletePrivate(privateMessage, botID: 3) },
        { try await fixture.repository.clearPrivate(botID: 3) },
        { try await fixture.repository.saveDraft("changed", kind: .privateChat, id: 3) },
        { try await fixture.repository.saveGroupMessage(groupMessage, groupID: 3, status: "changed") },
        { try await fixture.repository.clearGroup(groupID: 3) },
        { try await fixture.repository.markGroupHistoryComplete(groupID: 3, revision: 9) },
        { try await fixture.repository.removeGroup(groupID: 3) },
        { try await fixture.repository.replaceBots([]) },
        { try await fixture.repository.replaceGroups([]) }
    ]
    for write in writes {
        do { try await write(); Issue.record("Stale repository accepted a write") }
        catch is CancellationError {}
    }
    let privateMessages = try await fixture.repository.privateMessages(botID: 3)
    let groupMessages = try await fixture.repository.groupMessages(groupID: 3)
    #expect(privateMessages.map(\.remoteID) == [17])
    #expect(privateMessages.first?.sortKey == 17)
    #expect(groupMessages.map(\.remoteID) == [17])
    #expect(groupMessages.first?.status == "synced")
    #expect(try await fixture.repository.draft(kind: .privateChat, id: 3) == "keep")
    #expect(try await fixture.repository.cachedGroup(id: 3)?.name == "keep")
    #expect(try await !fixture.repository.isHistoryComplete(kind: .group, id: 3))
}

@Test func deletingSyncedSnapshotUsesRemoteIDInsteadOfPayloadUUID() async throws {
    let fixture = RepositoryFixture()
    try await fixture.repository.syncPrivate(botID: 3)
    let restored = try await fixture.repository.privateMessages(botID: 3)
    let first = try #require(restored.first)
    // finishSnapshot owns the SQLite row ID; the Codable payload has its own UUID.
    try await fixture.repository.deletePrivate(first.value, botID: 3)
    let remaining = try await fixture.repository.privateMessages(botID: 3)
    #expect(remaining.map(\.remoteID) == [2])
}
