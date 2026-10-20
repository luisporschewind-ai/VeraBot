import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking
@testable import VeraBotData

// MARK: - Fixtures

private func decode<T: Decodable>(_ value: Any) throws -> T {
    let data = try JSONSerialization.data(withJSONObject: value)
    return try JSONDecoder().decode(T.self, from: data)
}

private func botJSON(id: Int = 7, name: String = "小满") -> [String: Any] {
    ["id": id, "name": name, "avatar": "🌊", "color": "#0F766E", "persona": "安静", "instructions": ""]
}

private func makeBot(id: Int = 7) throws -> Bot {
    try decode(botJSON(id: id))
}

private func makeEncounter(endedAt: Double? = nil, turns: [DriftBottleTurn] = [],
                           expiresAt: Double = 90_000) -> DriftBottleEncounter {
    DriftBottleEncounter(
        id: 1, bottleID: 2, botID: 7, botName: "小满", botAvatar: "🌊",
        botColor: "#0F766E", botDeleted: false, startedAt: 1_000, expiresAt: expiresAt,
        endedAt: endedAt, endReason: endedAt == nil ? nil : .returned, version: 2,
        bottleVersion: 3, leaseToken: "lease-token-value", readLimit: 1, quiet: false,
        remainingSeconds: 1_000, isExpired: false, canPublish: endedAt == nil,
        contributions: [], nextCursor: nil, turns: turns, memory: nil)
}

private func encounterObject(_ encounter: DriftBottleEncounter) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(encounter))
}

private func makeState(current: DriftBottleEncounter?) throws -> DriftBottleState {
    let currentObject: Any = current.map { try? encounterObject($0) } ?? NSNull()
    return try decode([
        "server_time": 1_000,
        "current": currentObject,
        "limits": [
            "max_contributions_per_bottle": 50, "hold_seconds": 86_400,
            "public_length_min": 1, "public_length_max": 1_000,
            "opening_max_length": 120, "chat_max_length": 300,
            "publish_per_minute": 5, "draw_per_minute": 10, "generate_per_minute": 10,
        ],
        "has_active_encounter": current?.isActive ?? false,
    ])
}

private func operationObject(requestID: String, kind: String = "release",
                             status: String = "committed") -> [String: Any] {
    ["request_id": requestID, "status": status, "kind": kind,
     "error_code": NSNull(), "error_message": NSNull(), "retryable": false]
}

private func makeReleaseResponse(requestID: String, encounter: DriftBottleEncounter)
    throws -> DriftBottleReleaseResponse {
    let record: [String: Any] = [
        "id": "encounter:\(encounter.id)", "kind": "encounter",
        "title": "和 小满 一起读了一封信", "subtitle": "一封信",
        "created_at": 1_000, "completed_at": 2_000,
        "encounter": try encounterObject(encounter), "release": NSNull(),
        "contributions": [], "turns": [], "memory": NSNull(),
    ]
    return try decode(["operation": operationObject(requestID: requestID), "record": record])
}

private func makeReleaseEnvelope(requestID: String, encounter: DriftBottleEncounter)
    throws -> DriftBottleOperationEnvelope {
    let response = try makeReleaseResponse(requestID: requestID, encounter: encounter)
    let record = try JSONSerialization.jsonObject(with: JSONEncoder().encode(response.record))
    return try decode([
        "operation": operationObject(requestID: requestID),
        "result": ["record": record],
    ])
}

private func makeDrawResponse(encounter: DriftBottleEncounter, requestID: String)
    throws -> DriftBottleDrawResponse {
    try decode([
        "operation": operationObject(requestID: requestID, kind: "draw"),
        "encounter": try encounterObject(encounter),
    ])
}

// MARK: - Fake API

private final class FakeDriftAPI: DriftBottleAPI, @unchecked Sendable {
    var stateResult: Result<DriftBottleState, Error>
    var drawHandler: (@Sendable () async throws -> DriftBottleDrawResponse)?
    var releaseHandler: (@Sendable (Int, DriftBottleReleaseRequest) async throws -> DriftBottleReleaseResponse)?
    var operationHandler: (@Sendable (String) async throws -> DriftBottleOperationEnvelope)?
    var turnHandler: (@Sendable (Int, DriftBottleTurnRequest) async throws -> DriftBottleTurnResponse)?
    private(set) var releaseRequests: [DriftBottleReleaseRequest] = []
    private(set) var operationRequests: [String] = []
    private(set) var turnRequests: [DriftBottleTurnRequest] = []

    init(state: DriftBottleState) { stateResult = .success(state) }

    func driftBottleState() async throws -> DriftBottleState { try stateResult.get() }

    func createDriftBottle(_ request: DriftBottleCreateRequest) async throws -> DriftBottleCreateResponse {
        throw APIError(status: 501, message: "unused")
    }

    func drawDriftBottle(_ request: DriftBottleDrawRequest) async throws -> DriftBottleDrawResponse {
        guard let drawHandler else { throw APIError(status: 501, message: "unused") }
        return try await drawHandler()
    }

    func driftBottleEncounter(id: Int, cursor: String?) async throws -> DriftBottleEncounter {
        throw APIError(status: 501, message: "unused")
    }

    func sendDriftBottleTurn(encounterID: Int, request: DriftBottleTurnRequest) async throws -> DriftBottleTurnResponse {
        turnRequests.append(request)
        guard let turnHandler else { throw APIError(status: 501, message: "unused") }
        return try await turnHandler(encounterID, request)
    }

    func releaseDriftBottle(encounterID: Int, request: DriftBottleReleaseRequest) async throws -> DriftBottleReleaseResponse {
        releaseRequests.append(request)
        guard let releaseHandler else { throw APIError(status: 501, message: "unused") }
        return try await releaseHandler(encounterID, request)
    }

    func generateDriftBottleMemory(encounterID: Int,
                                   request: DriftBottleMemoryRequest) async throws -> DriftBottleMemoryResponse {
        throw APIError(status: 501, message: "unused")
    }

    func driftBottleDraftSuggestion(_ request: DriftBottleDraftSuggestionRequest)
        async throws -> DriftBottleDraftSuggestionResponse {
        throw APIError(status: 501, message: "unused")
    }

    func driftBottleRecords(botID: Int?, cursor: String?, limit: Int) async throws -> DriftBottleRecordsResponse {
        throw APIError(status: 501, message: "unused")
    }

    func driftBottleRecord(id: String) async throws -> DriftBottleRecord {
        throw APIError(status: 501, message: "unused")
    }

    func patchDriftBottleMemory(recordID: String, requestID: String,
                                patch: DriftBottleMemoryPatch) async throws -> DriftBottleMemoryResponse {
        throw APIError(status: 501, message: "unused")
    }

    func deleteDriftBottleMemory(recordID: String, requestID: String) async throws -> DriftBottleDeleteResponse {
        throw APIError(status: 501, message: "unused")
    }

    func deleteDriftBottleRecord(id: String, requestID: String) async throws -> DriftBottleDeleteResponse {
        throw APIError(status: 501, message: "unused")
    }

    func withdrawDriftBottleContribution(id: Int,
                                         request: DriftBottleWithdrawRequest) async throws -> DriftBottleWithdrawResponse {
        throw APIError(status: 501, message: "unused")
    }

    func reportDriftBottleContribution(_ request: DriftBottleReportRequest) async throws -> DriftBottleReportResponse {
        throw APIError(status: 501, message: "unused")
    }

    func blockDriftBottleContributor(_ request: DriftBottleBlockRequest) async throws -> DriftBottleBlockResponse {
        throw APIError(status: 501, message: "unused")
    }

    func driftBottleOperation(requestID: String) async throws -> DriftBottleOperationEnvelope {
        operationRequests.append(requestID)
        guard let operationHandler else { throw APIError(status: 501, message: "unused") }
        return try await operationHandler(requestID)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.withLock { value += 1; return value } }
}

private final class DrawGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DriftBottleDrawResponse, Error>?
    private var _started = false

    var started: Bool { lock.withLock { _started } }

    func wait() async throws -> DriftBottleDrawResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
                _started = true
            }
        }
    }

    func resume(_ response: DriftBottleDrawResponse) {
        let continuation = lock.withLock {
            let value = self.continuation
            self.continuation = nil
            return value
        }
        continuation?.resume(returning: response)
    }
}

// MARK: - Tests

@Suite(.serialized) struct DriftBottleModelTests {
    private func temporaryCache() -> (DriftBottleDraftCache, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-cache-\(UUID().uuidString)", isDirectory: true)
        return (DriftBottleDraftCache(root: root), root)
    }

    @Test @MainActor func draftAndSelectedBotStayInsideOneAccount() async throws {
        let (cache, root) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeDriftAPI(state: try makeState(current: nil))
        let bot = try makeBot()

        let first = DriftBottleModel(cache: cache, requestID: { "request-test-1" })
        await first.configure(api: fake, server: "server-a", userID: 1)
        first.updateBots([bot])
        first.selectBot(7)
        first.saveDraft(text: "我自己的草稿", authorship: .owner, forNewBottle: true)
        await first.flushCache()

        let reopened = DriftBottleModel(cache: cache)
        await reopened.configure(api: fake, server: "server-a", userID: 1)
        #expect(reopened.selectedBotID == 7)
        #expect(reopened.draft(forNewBottle: true)?.text == "我自己的草稿")

        let otherAccount = DriftBottleModel(cache: cache)
        await otherAccount.configure(api: fake, server: "server-a", userID: 2)
        #expect(otherAccount.selectedBotID == nil)
        #expect(otherAccount.draft(forNewBottle: true) == nil)

        let stem = DriftBottleDraftCache.fileStem(scope: "server-a|1")
        let raw = try String(contentsOf: root.appendingPathComponent(stem + ".json"), encoding: .utf8)
        #expect(raw.contains("我自己的草稿"))
        #expect(!raw.contains("陌生人的原文"))
    }

    @Test @MainActor func lateDrawAfterAccountSwitchIsDropped() async throws {
        let (cache, root) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeDriftAPI(state: try makeState(current: nil))
        let gate = DrawGate()
        fake.drawHandler = { try await gate.wait() }
        let model = DriftBottleModel(cache: cache)

        await model.configure(api: fake, server: "server-a", userID: 1)
        model.updateBots([try makeBot()])
        async let pending = model.draw(botID: 7)
        for _ in 0..<2_000 where !gate.started { await Task.yield() }
        #expect(gate.started)

        model.reset(accountID: 1)
        await model.configure(api: fake, server: "server-a", userID: 2)
        gate.resume(try makeDrawResponse(encounter: makeEncounter(), requestID: "draw-late"))
        let result = await pending
        #expect(result == nil)
        #expect(model.current == nil)
    }

    @Test @MainActor func unknownReleaseReusesRequestIDAndQueriesBeforeResend() async throws {
        let (cache, root) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let encounter = makeEncounter()
        let fake = FakeDriftAPI(state: try makeState(current: encounter))
        fake.operationHandler = { _ in throw APIError(status: 404, message: "not yet") }
        let attempts = Counter()
        fake.releaseHandler = { _, request in
            let current = attempts.increment()
            if current == 1 { throw URLError(.timedOut) }
            return try makeReleaseResponse(requestID: request.requestID, encounter: encounter)
        }
        let model = DriftBottleModel(cache: cache)
        await model.configure(api: fake, server: "server-a", userID: 1)
        model.updateBots([try makeBot()])
        #expect(model.current?.id == encounter.id)

        #expect(await model.release(contribution: nil) == nil)
        #expect(model.pendingRelease != nil)
        let record = await model.release(contribution: nil)
        #expect(record?.id == "encounter:1")
        #expect(fake.releaseRequests.count == 2)
        #expect(fake.releaseRequests[0].requestID == fake.releaseRequests[1].requestID)
        #expect(model.pendingRelease == nil)
        #expect(model.current == nil)
    }

    @Test @MainActor func committedPendingOperationIsAppliedWithoutResending() async throws {
        let (cache, root) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let encounter = makeEncounter()
        let fake = FakeDriftAPI(state: try makeState(current: encounter))
        fake.operationHandler = { _ in throw APIError(status: 404, message: "not yet") }
        fake.releaseHandler = { _, _ in throw URLError(.timedOut) }
        let model = DriftBottleModel(cache: cache)
        await model.configure(api: fake, server: "server-a", userID: 1)
        model.updateBots([try makeBot()])
        #expect(await model.release(contribution: nil) == nil)
        let requestID = try #require(model.pendingRelease?.requestID)

        fake.operationHandler = { _ in try makeReleaseEnvelope(requestID: requestID, encounter: encounter) }
        await model.recoverPendingOperations()
        #expect(fake.releaseRequests.count == 1)
        #expect(fake.operationRequests == [requestID])
        #expect(model.pendingRelease == nil)
        #expect(model.current == nil)
        #expect(model.lastCompletedRecord?.id == "encounter:1")
    }

    @Test @MainActor func offlineRestoresPrivateTurnsButNotPublicBodies() async throws {
        let (cache, root) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let turn = DriftBottleTurn(id: 1, role: .user, kind: .chat,
                                   content: "这是我说过的话", createdAt: 1_000)
        let cached = DriftBottleCachedEncounter(
            id: 1, bottleID: 2, botID: 7, botName: "小满", botAvatar: "🌊",
            botColor: "#0F766E", readLimit: 1, expiresAt: 90_000, endedAt: nil,
            endReason: nil, turns: [turn])
        let local = DriftBottleLocalRecord(
            scope: "server-a|1", selectedBotID: 7, activeEncounter: cached,
            drafts: ["new": DriftBottleDraft(text: "草稿还在", authorship: .owner, generated: false,
                                             updatedAt: Date(timeIntervalSince1970: 1_000))],
            pendingOperations: [])
        try await cache.save(local, scope: "server-a|1")

        let fake = FakeDriftAPI(state: try makeState(current: nil))
        fake.stateResult = .failure(URLError(.notConnectedToInternet))
        let model = DriftBottleModel(cache: cache)
        await model.configure(api: fake, server: "server-a", userID: 1)
        #expect(model.isOffline)
        #expect(model.current == nil)
        #expect(model.privateTurns.map(\.content) == ["这是我说过的话"])
        #expect(model.draft(forNewBottle: true)?.text == "草稿还在")
        #expect(model.offlineMessage?.contains("需要联网更新") == true)
    }

    @Test @MainActor func resetClearsAccountScopedState() async throws {
        let (cache, root) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeDriftAPI(state: try makeState(current: makeEncounter()))
        let model = DriftBottleModel(cache: cache)
        await model.configure(api: fake, server: "server-a", userID: 1)
        model.updateBots([try makeBot()])
        #expect(model.current != nil)
        model.reset(accountID: 1)
        #expect(model.current == nil)
        #expect(model.selectedBotID == nil)
        #expect(model.bots.isEmpty)
        #expect(model.state == nil)
    }

    @Test @MainActor func expiredEncounterStillAllowsPrivateChat() async throws {
        let (cache, root) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let encounter = makeEncounter(endedAt: 50_000)
        let fake = FakeDriftAPI(state: try makeState(current: encounter))
        fake.turnHandler = { _, request in
            var returned = encounter
            returned.turns = [DriftBottleTurn(id: 9, role: .bot, kind: .chat,
                                              content: "我还记得那封信。", createdAt: 2_000)]
            return try decode([
                "operation": operationObject(requestID: request.requestID, kind: "turn"),
                "encounter": try encounterObject(returned),
                "turn": ["id": 9, "role": "bot", "kind": "chat", "content": "我还记得那封信。",
                         "created_at": 2_000],
                "draft": NSNull(),
            ])
        }
        let model = DriftBottleModel(cache: cache)
        await model.configure(api: fake, server: "server-a", userID: 1)
        #expect(model.current?.isActive == false)
        let sent = await model.send(message: "还能继续聊吗？")
        #expect(sent)
        #expect(model.privateTurns.last?.content == "我还记得那封信。")
    }
}
