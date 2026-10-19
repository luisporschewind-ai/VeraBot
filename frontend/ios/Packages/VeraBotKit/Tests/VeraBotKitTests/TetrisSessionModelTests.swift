import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotData
@testable import VeraBotNetworking

private let install = "00000000-0000-0000-0000-000000000001"
private let remoteID = "00000000-0000-0000-0000-000000000002"
private enum CacheFault: Error { case injected }
private actor TestTetrisCache: TetrisSessionCaching {
    var values: [TetrisCacheScope: TetrisCacheRecord] = [:]
    var failOnSave: Int?
    var saves = 0
    init(failOnSave: Int? = nil) { self.failOnSave = failOnSave }
    func load(_ scope: TetrisCacheScope) -> TetrisCacheRecord? { values[scope] }
    func save(_ record: TetrisCacheRecord, scope: TetrisCacheScope) throws {
        saves += 1
        if saves == failOnSave { throw CacheFault.injected }
        values[scope] = record
    }
    func remove(_ scope: TetrisCacheScope) { values[scope] = nil }
}
private actor TestTetrisAPI: TetrisSessionAPI {
    enum Mode: Sendable { case commit, timeoutAfterCommit, timeoutBeforeCommit, delayed, delayedCapabilities, rejectCreate, timeoutThenReject, delayedEnd }
    var mode: Mode
    let rejectionStatus: Int
    var creates: [TetrisHandoffRequest] = []
    var commands: [TetrisCommandRequest] = []
    var remote: TetrisRemoteSession?
    var operations: [String:TetrisOperation] = [:]
    var continuation: CheckedContinuation<TetrisOperation, any Error>?
    init(mode: Mode = .commit, rejectionStatus: Int = 503) { self.mode = mode; self.rejectionStatus = rejectionStatus }
    var capabilityWait: CheckedContinuation<TetrisCapabilities, Never>?
    func tetrisCapabilities() async -> TetrisCapabilities {
        if mode == .delayedCapabilities { return await withCheckedContinuation { capabilityWait = $0 } }
        return .init(available: true, workerReady: true)
    }
    func isCapabilityWaiting() -> Bool { capabilityWait != nil }
    func finishCapabilities() { capabilityWait?.resume(returning: .init(available: false, workerReady: false)); capabilityWait = nil }
    func currentTetrisSession() -> TetrisRemoteSession? { remote }
    func createTetrisSession(_ request: TetrisHandoffRequest) async throws -> TetrisOperation {
        creates.append(request)
        if mode == .rejectCreate { throw APIError(status: rejectionStatus, message: "rejected") }
        if mode == .timeoutThenReject { mode = .rejectCreate; throw URLError(.timedOut) }
        if mode == .timeoutBeforeCommit { mode = .commit; throw URLError(.timedOut) }
        var game = try TetrisGame(restoring: request.snapshot)
        if game.state.phase == .ready { game.apply(.start) }
        if game.state.phase == .paused { game.apply(.resume) }
        let value = TetrisRemoteSession(id: remoteID, originClientID: request.clientID, botID: request.botID, controller: .bot, runState: .running, version: 1, controlEpoch: 1, latestSnapshot: game.state, contribution: .init(playerScore: game.score, playerLines: game.lines, botScore: 0, botLines: 0), updatedAt: 1)
        remote = value
        let result = TetrisOperation(requestID: request.requestID, status: .committed, session: value)
        operations[request.requestID] = result
        if mode == .timeoutAfterCommit { throw URLError(.timedOut) }
        if mode == .delayed { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return result
    }
    func tetrisSession(id: String, afterVersion: Int64?, afterEventSequence: Int64?) throws -> TetrisRemoteSession {
        guard let remote else { throw APIError(status: 404, message: "missing") }; return remote
    }
    func tetrisOperation(requestID: String) throws -> TetrisOperation {
        guard let result = operations[requestID] else { throw APIError(status: 404, message: "missing") }; return result
    }
    func commandTetrisSession(id: String, request: TetrisCommandRequest) async throws -> TetrisOperation {
        commands.append(request)
        guard var value = remote else { throw APIError(status: 404, message: "missing") }
        value.version += 1
        if request.command == .reclaim { value.pendingOperation = request.requestID }
        if request.command == .end { value.runState = .over; value.controlEpoch += 1 }
        let result = TetrisOperation(requestID: request.requestID, status: request.command == .reclaim ? .pending : .committed, session: value)
        remote = value; operations[request.requestID] = result
        if mode == .delayedEnd && request.command == .end { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return result
    }
    func advanceBot() throws {
        var value = remote!
        var game = try TetrisGame(restoring: value.latestSnapshot)
        game.apply(.hardDrop)
        value.contribution.botScore += game.score - value.latestSnapshot.score
        value.contribution.botLines += game.lines - value.latestSnapshot.lines
        value.latestSnapshot = game.state; value.eventCursor = game.state.eventSequence; value.version += 1
        remote = value
    }
    func completeReclaim() throws {
        let request = commands.last!
        var value = remote!
        var game = try TetrisGame(restoring: value.latestSnapshot); game.apply(.pause)
        value.latestSnapshot = game.state; value.eventCursor = game.state.eventSequence
        value.controller = .player; value.runState = .paused; value.version += 1; value.controlEpoch += 1; value.pendingOperation = nil
        remote = value; operations[request.requestID] = .init(requestID: request.requestID, status: .committed, session: value)
    }
    func delayEndReplies() { mode = .delayedEnd }
    func finishLastCommand() { continuation?.resume(returning: operations[commands.last!.requestID]!); continuation = nil }
    func finishCreate() { continuation?.resume(returning: operations[creates.last!.requestID]!); continuation = nil }
    func isWaiting() -> Bool { continuation != nil }
}
@MainActor @Suite struct TetrisSessionModelTests {
    private func game() -> TetrisState {
        var game = TetrisGame(seed: 42, ruleVersion: "vera-tetris-2"); game.apply(.start); game.apply(.pause); return game.state
    }
    private func model(cache: any TetrisSessionCaching = TestTetrisCache()) -> TetrisSessionModel {
        TetrisSessionModel(clientID: install, cache: cache, automaticallyPoll: false)
    }
    @Test func firstExplicitRejectionDoesNotLeaveUnrecoverablePending() async {
        for status in [403, 404, 409, 413, 422, 503] {
            let api = TestTetrisAPI(mode: .rejectCreate, rejectionStatus: status), model = model()
            await model.configure(api: api, server: "https://one.test", userID: 1)
            await model.handoff(snapshot: game(), botID: 7)
            #expect(model.phase == .local && model.canRunLocal && model.control.pending == nil, "Explicit first rejection: \(status)")
            #expect(await api.creates.count == 1)
        }
    }
    @Test func restoredPendingIsUncertainEvenIfProcessDiedBeforeWritingTimeoutFlag() async throws {
        let cache = TestTetrisCache(), api = TestTetrisAPI(mode: .rejectCreate), model = model(cache: cache)
        let request = TetrisHandoffRequest(clientID: install, botID: 7, snapshot: game())
        try await cache.save(.init(remote: nil, pending: .create(request), localSnapshot: nil, uncertainAttempt: false), scope: .init(server: "https://one.test", userID: 1, clientID: install))
        await model.configure(api: api, server: "https://one.test", userID: 1)
        #expect(model.phase == .pending && !model.canRunLocal)
        #expect(model.control.pending?.requestID == request.requestID)
    }
    @Test func rejectionOfRetryCannotProveOriginalTimedOutWriteNeverCommitted() async {
        let api = TestTetrisAPI(mode: .timeoutThenReject), model = model()
        await model.configure(api: api, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: game(), botID: 7)
        let original = model.control.pending?.requestID
        await model.recoverPending()
        #expect(model.phase == .pending && !model.canRunLocal)
        #expect(model.control.pending?.requestID == original)
    }
    @Test func oldRestartCannotDetachNewAccountFromItsCloudRound() async throws {
        let old = TestTetrisAPI(), model = model()
        await model.configure(api: old, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: game(), botID: 7); await model.reclaim()
        try await old.completeReclaim(); await model.recoverPending()
        await old.delayEndReplies()
        let restart = Task { await model.newLocalRound() }
        for _ in 0..<1000 { if await old.isWaiting() { break }; await Task.yield() }
        #expect(await old.isWaiting())
        let current = TestTetrisAPI()
        _ = try await current.createTetrisSession(.init(clientID: install, botID: 8, snapshot: game()))
        await model.configure(api: current, server: "https://two.test", userID: 2)
        await old.finishLastCommand(); await restart.value
        #expect(model.phase == .botRunning && !model.canRunLocal && !model.control.viewingSeparateLocal)
        #expect(model.remote?.botID == 8)
    }
    @Test func restartingAReclaimedLocalRoundCanHandoffTheNewRound() async throws {
        let api = TestTetrisAPI(), model = model()
        await model.configure(api: api, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: game(), botID: 7); await model.reclaim()
        try await api.completeReclaim(); await model.recoverPending()
        await model.newLocalRound()
        #expect(model.phase == .local && model.remote == nil && model.canHandoff)
    }
    @Test func lateLocalSaveCannotRollBackConfirmedReclaimedProgress() async throws {
        let api = TestTetrisAPI(), model = model()
        let old = game()
        await model.configure(api: api, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: old, botID: 7)
        try await api.advanceBot(); await model.refresh(); await model.reclaim()
        try await api.completeReclaim(); await model.recoverPending()
        let confirmed = model.displaySnapshot
        #expect((confirmed?.score ?? 0) > old.score)
        await model.persistLocal(old, expectedScope: model.cacheScope)
        #expect(model.displaySnapshot == confirmed)
    }
    @Test func accountChangeFencesLateCapabilities() async {
        let old = TestTetrisAPI(mode: .delayedCapabilities), model = model()
        let work = Task { await model.configure(api: old, server: "https://one.test", userID: 1) }
        for _ in 0..<1000 { if await old.isCapabilityWaiting() { break }; await Task.yield() }
        #expect(await old.isCapabilityWaiting())
        await model.configure(api: TestTetrisAPI(), server: "https://two.test", userID: 2)
        await old.finishCapabilities(); await work.value
        #expect(model.capabilities?.available == true)
    }
    @Test func independentLocalRoundPreservesPendingRecovery() async {
        let api = TestTetrisAPI(mode: .timeoutAfterCommit), model = model()
        await model.configure(api: api, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: game(), botID: 7)
        let id = model.control.pending?.requestID
        model.startSeparateLocalRound()
        #expect(model.canRunLocal && model.displaySnapshot == nil)
        #expect(model.control.pending?.requestID == id && !model.canHandoff)
        await model.recoverPending()
        #expect(model.canRunLocal && model.control.viewingSeparateLocal)
        model.watchRemote()
        #expect(!model.canRunLocal && model.phase == .botRunning)
    }
    @Test func delayedLocalSaveCannotWriteIntoAnotherAccount() async throws {
        let api = TestTetrisAPI(), cache = TestTetrisCache(), model = model(cache: cache)
        await model.configure(api: api, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: game(), botID: 7); await model.reclaim()
        try await api.completeReclaim(); await model.recoverPending()
        let oldScope = model.cacheScope
        await model.configure(api: api, server: "https://one.test", userID: 2)
        let before = await cache.saves
        await model.persistLocal(game(), expectedScope: oldScope)
        #expect(await cache.saves == before && model.localSnapshot == nil)
    }
    @Test func watchingAfterHandoffDoesNotAccidentallyDetachIntoLocalControl() async {
        let api = TestTetrisAPI(), model = model()
        await model.configure(api: api, server: "https://one.test", userID: 1)
        model.markLocalActivity()
        await model.handoff(snapshot: game(), botID: 7)
        await model.refresh()
        #expect(model.phase == .botRunning && !model.canRunLocal)
        #expect(!model.control.viewingSeparateLocal)
    }
    @Test func timeoutAfterCommitQueriesOriginalOperationWithoutNewCreate() async throws {
        let api = TestTetrisAPI(mode: .timeoutAfterCommit), cache = TestTetrisCache()
        let actual = self.model(cache: cache)
        await actual.configure(api: api, server: "https://one.test", userID: 1)
        await actual.handoff(snapshot: game(), botID: 7)
        #expect(actual.phase == .pending && !actual.canRunLocal)
        let before = await api.creates
        await actual.recoverPending()
        #expect(actual.phase == .botRunning && actual.remote?.id == remoteID)
        #expect(await api.creates.count == 1)
        let cached = await cache.load(.init(server: "https://one.test", userID: 1, clientID: install))
        #expect(cached?.pending == nil && before.count == 1)
    }
    @Test func unknownOperationRetriesTheExactPersistedRequest() async {
        let api = TestTetrisAPI(mode: .timeoutBeforeCommit), model = model()
        await model.configure(api: api, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: game(), botID: 7)
        await model.recoverPending()
        let requests = await api.creates
        #expect(requests.count == 2 && requests[0] == requests[1])
        #expect(model.phase == .botRunning)
    }
    @Test func writeCannotLeaveDeviceBeforePendingIsSaved() async {
        let api = TestTetrisAPI(), cache = TestTetrisCache(failOnSave: 1), model = model(cache: cache)
        await model.configure(api: api, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: game(), botID: 7)
        #expect(await api.creates.isEmpty)
        #expect(model.phase == .local && model.canRunLocal)
    }
    @Test func failedCacheAfterAcknowledgmentCannotRestoreLocalControl() async {
        let api = TestTetrisAPI(), cache = TestTetrisCache(failOnSave: 2), model = model(cache: cache)
        await model.configure(api: api, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: game(), botID: 7)
        #expect(model.phase == .botRunning && !model.canRunLocal)
        let cached = await cache.load(.init(server: "https://one.test", userID: 1, clientID: install))
        #expect(cached?.pending != nil)
    }
    @Test func accountChangeFencesLateAcknowledgmentAndPreservesOldRecoveryRecord() async throws {
        let old = TestTetrisAPI(mode: .delayed), cache = TestTetrisCache(), model = model(cache: cache)
        await model.configure(api: old, server: "https://one.test", userID: 1)
        let work = Task { await model.handoff(snapshot: game(), botID: 7) }
        for _ in 0..<1000 { if await old.isWaiting() { break }; await Task.yield() }
        #expect(await old.isWaiting())
        await model.configure(api: TestTetrisAPI(), server: "https://two.test", userID: 2)
        await old.finishCreate(); await work.value
        #expect(model.remote == nil && model.phase == .local)
        let previous = await cache.load(.init(server: "https://one.test", userID: 1, clientID: install))
        let current = await cache.load(.init(server: "https://two.test", userID: 2, clientID: install))
        #expect(previous?.pending != nil && current == nil)
    }
    @Test func reclaimDoesNotUnlockUntilCommittedSnapshotReturns() async throws {
        let api = TestTetrisAPI(), model = model()
        await model.configure(api: api, server: "https://one.test", userID: 1)
        await model.handoff(snapshot: game(), botID: 7); await model.reclaim()
        #expect(model.phase == .pending && !model.canRunLocal)
        try await api.completeReclaim(); await model.recoverPending()
        #expect(model.phase == .returned && model.canRunLocal)
        #expect(model.displaySnapshot?.phase == .paused)
        #expect(model.displaySnapshot?.rngState == game().rngState)
    }
    @Test func realCacheIsScopedAtomicAndChecksCorruption() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TetrisSessionCache(directory: directory)
        let scope = TetrisCacheScope(server: "https://one.test", userID: 1, clientID: install)
        let request = TetrisHandoffRequest(clientID: install, botID: 7, snapshot: game())
        let record = TetrisCacheRecord(remote: nil, pending: .create(request), localSnapshot: nil)
        try await cache.save(record, scope: scope)
        let reloaded = try await TetrisSessionCache(directory: directory).load(scope)
        #expect(reloaded == record)
        #expect(try await cache.load(.init(server: "https://one.test", userID: 2, clientID: install)) == nil)
        let path = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var bytes = try Data(contentsOf: path); bytes[bytes.count/2] ^= 1; try bytes.write(to: path)
        do { _ = try await cache.load(scope); Issue.record("corrupt cache accepted") } catch {}
    }
}
