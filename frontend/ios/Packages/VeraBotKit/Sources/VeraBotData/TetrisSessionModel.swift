import Foundation
import Observation
import VeraBotCore
import VeraBotNetworking

@MainActor @Observable public final class TetrisSessionModel {
    public private(set) var control: TetrisSessionControl
    public private(set) var isReady = false
    public private(set) var capabilities: TetrisCapabilities?
    public private(set) var message: String?
    public private(set) var localSnapshot: TetrisState?
    public var cacheScope: TetrisCacheScope? { scope }
    public var phase: TetrisControlPhase { control.phase }
    public var remote: TetrisRemoteSession? { control.remote }
    public var canRunLocal: Bool { isReady && control.canRunLocal }
    public var canCommand: Bool { isReady && control.canCommand && remote?.pendingOperation == nil }
    public var canHandoff: Bool {
        isReady && !control.viewingSeparateLocal && control.pending == nil &&
        (phase == .local || phase == .returned) && capabilities?.compatible == true && capabilities?.available == true
    }
    public var displaySnapshot: TetrisState? {
        guard !control.viewingSeparateLocal, phase != .local else { return nil }
        if case .create(let request) = control.pending { return request.snapshot }
        if case .command(_, let request) = control.pending, request.command == .handoff { return request.snapshot }
        if phase == .returned, let localSnapshot { return localSnapshot }
        return remote?.latestSnapshot
    }
    public var statusText: String {
        if control.viewingSeparateLocal { return "正在玩本地新局，原代玩记录仍保留" }
        switch phase {
        case .pending: return "正在确认交接，本局操作暂时锁定"
        case .botRunning: return "Bot 正在替你玩，离开 App 也会继续"
        case .botPaused: return "Bot 已暂停，等你回来"
        case .returned: return "已经交还给你，点继续再开始"
        case .ended: return "这一局代玩结束了"
        case .recoveryRequired: return "云端状态待确认，可重试或另开本地局"
        case .local:
            if capabilities?.available == true && capabilities?.compatible == true { return "伙伴在身边，也可以替你玩" }
            return "本地游戏可离线玩，代玩服务尚未就绪"
        }
    }
    @ObservationIgnored private let clientID: String
    @ObservationIgnored private let cache: any TetrisSessionCaching
    @ObservationIgnored private let automaticallyPoll: Bool
    @ObservationIgnored private var api: (any TetrisSessionAPI)?
    @ObservationIgnored private var scope: TetrisCacheScope?
    @ObservationIgnored private var scopeEpoch: UInt64 = 0
    @ObservationIgnored private var cacheTail: Task<Void, any Error>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var active = true
    @ObservationIgnored private var recovering = false
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var didBeginLocal = false
    @ObservationIgnored private var uncertainAttempt = false
    @ObservationIgnored private var failureCount = 0

    public convenience init(clientID: String, cache: any TetrisSessionCaching = TetrisSessionCache()) {
        self.init(clientID: clientID, cache: cache, automaticallyPoll: true)
    }
    init(clientID: String, cache: any TetrisSessionCaching, automaticallyPoll: Bool) {
        self.clientID = clientID; self.cache = cache; self.automaticallyPoll = automaticallyPoll
        control = TetrisSessionControl(clientID: clientID)
    }
    public func clearAccount() {
        scopeEpoch &+= 1; pollTask?.cancel(); pollTask = nil
        api = nil; scope = nil; control.reset(); localSnapshot = nil; capabilities = nil
        isReady = true; message = nil; recovering = false; refreshing = false; didBeginLocal = false
    }
    public func configure(api: any TetrisSessionAPI, server: String, userID: Int) async {
        scopeEpoch &+= 1; let epoch = scopeEpoch
        pollTask?.cancel(); pollTask = nil; active = true
        self.api = api; scope = .init(server: server, userID: userID, clientID: clientID)
        control.reset(); localSnapshot = nil; isReady = false; capabilities = nil; message = nil
        recovering = false; refreshing = false; uncertainAttempt = false; didBeginLocal = false; failureCount = 0
        do {
            try? await cacheTail?.value
            guard epoch == scopeEpoch, let scope else { return }
            let record = try await cache.load(scope)
            guard epoch == scopeEpoch else { return }
            if let record {
                try control.restore(remote: record.remote, pending: record.pending)
                uncertainAttempt = record.uncertainAttempt || record.pending != nil
                if let candidate = record.localSnapshot, let remote = record.remote,
                   remote.controller == .player, remote.originClientID == clientID,
                   candidate.eventSequence >= remote.latestSnapshot.eventSequence,
                   candidate.score >= remote.latestSnapshot.score, candidate.lines >= remote.latestSnapshot.lines {
                    _ = try TetrisGame(restoring: candidate); localSnapshot = candidate
                }
                if control.pending != nil { isReady = true; await recoverPending() }
                else { await loadAuthority(epoch: epoch) }
            } else {
                // An unrelated local game never depends on availability of the server.
                isReady = true
                await loadAuthority(epoch: epoch)
            }
            guard epoch == scopeEpoch else { return }
            if active {
                do {
                    let latest = try await api.tetrisCapabilities()
                    guard epoch == scopeEpoch else { return }
                    capabilities = latest
                }
                catch { if epoch == scopeEpoch && control.remote == nil && control.pending == nil { message = "代玩服务暂不可用，本地游戏不受影响" } }
            }
        } catch {
            guard epoch == scopeEpoch else { return }
            control.markUncertain(); isReady = true; message = "本机恢复记录暂不可用，请重试确认云端状态"
        }
        if epoch == scopeEpoch { startPolling() }
    }
    public func markLocalActivity() { didBeginLocal = true }
    public func startSeparateLocalRound() { control.startSeparateLocalRound(); localSnapshot = nil; isReady = true; didBeginLocal = true }
    public func newLocalRound() async {
        let epoch = scopeEpoch
        // A confirmed restart also closes the previous returned server record.
        // If the result is unknown, a separate local game remains safe to play.
        if phase == .returned, control.pending == nil, remote?.originClientID == clientID {
            await endRound()
            guard epoch == scopeEpoch else { return }
        }
        if control.pending == nil && (remote == nil || remote?.runState == .over) {
            control.reset(); localSnapshot = nil; isReady = true; didBeginLocal = true
            let previous = cacheTail; let cache = cache
            if let scope {
                let work = Task { try? await previous?.value; try await cache.remove(scope) }
                cacheTail = work; try? await work.value
            }
        } else { startSeparateLocalRound() }
    }
    public func watchRemote() { control.watchRemote(); startPolling() }
    public func setActive(_ value: Bool) {
        active = value; pollTask?.cancel(); pollTask = nil
        if value { startPolling(immediate: true) }
    }
    public func stopObserving() {
        active = false; scopeEpoch &+= 1; pollTask?.cancel(); pollTask = nil
    }
    public func persistLocal(_ snapshot: TetrisState, expectedScope: TetrisCacheScope? = nil, expectedGeneration: UInt64? = nil) async {
        guard expectedScope == nil || expectedScope == scope else { return }
        guard expectedGeneration == nil || expectedGeneration == control.generation else { return }
        guard phase == .returned, !control.viewingSeparateLocal, remote?.originClientID == clientID else { return }
        guard let reference = localSnapshot ?? remote?.latestSnapshot,
              snapshot.eventSequence >= reference.eventSequence,
              snapshot.logicalTimeMs >= reference.logicalTimeMs,
              snapshot.score >= reference.score, snapshot.lines >= reference.lines else { return }
        let epoch = scopeEpoch
        do { _ = try TetrisGame(restoring: snapshot); localSnapshot = snapshot; try await persist() }
        catch { if epoch == scopeEpoch { message = "本局已暂停，本机进度暂未保存" } }
    }
    private func persist() async throws {
        guard let scope else { return }
        let record = TetrisCacheRecord(remote: remote, pending: control.pending, localSnapshot: localSnapshot, uncertainAttempt: uncertainAttempt)
        let previous = cacheTail; let cache = cache
        let work = Task {
            try? await previous?.value
            try await cache.save(record, scope: scope)
        }
        cacheTail = work
        try await work.value
    }
    public func handoff(snapshot: TetrisState, botID: Int) async {
        guard canHandoff else { message = "代玩暂不可用，请先确认服务与当前交接状态"; return }
        let write: TetrisWrite
        if let remote, phase == .returned {
            write = .command(sessionID: remote.id, request: .init(clientID: clientID, expectedVersion: remote.version, expectedEpoch: remote.controlEpoch, command: .handoff, botID: botID, snapshot: snapshot))
        } else { write = .create(.init(clientID: clientID, botID: botID, snapshot: snapshot)) }
        localSnapshot = snapshot
        await begin(write)
    }
    public func reclaim() async { await command(.reclaim) }
    public func pauseBot() async { await command(.pauseBot) }
    public func resumeBot() async { await command(.resumeBot) }
    public func endRound() async { await command(.end) }
    public func changeBot(id: Int) async { await command(.changeBot, botID: id) }
    private func command(_ command: TetrisCommand, botID: Int? = nil) async {
        guard canCommand, let remote else { message = "请先确认状态，并在交出游戏的原设备操作"; return }
        await begin(.command(sessionID: remote.id, request: .init(clientID: clientID, expectedVersion: remote.version, expectedEpoch: remote.controlEpoch, command: command, botID: botID)))
    }
    private func begin(_ write: TetrisWrite) async {
        guard api != nil, scope != nil else { return }
        let epoch = scopeEpoch
        let token: UInt64
        do { token = try control.begin(write); didBeginLocal = false; uncertainAttempt = false; message = nil; try await persist() }
        catch {
            if epoch == scopeEpoch { control.rejectWrite(); message = "无法保存交接记录，尚未发出请求，本局已暂停" }
            return
        }
        guard epoch == scopeEpoch, !Task.isCancelled else { return }
        await submit(write, epoch: epoch, token: token)
        if epoch == scopeEpoch { startPolling() }
    }
    private func submit(_ write: TetrisWrite, epoch: UInt64, token: UInt64) async {
        guard let api, epoch == scopeEpoch else { return }
        let result: TetrisOperation
        do {
            switch write {
            case .create(let request): result = try await api.createTetrisSession(request)
            case .command(let id, let request): result = try await api.commandTetrisSession(id: id, request: request)
            }
        } catch {
            guard epoch == scopeEpoch, token == control.generation else { return }
            // Only a first, explicit rejection proves this attempt did not commit.
            // A restored or timed-out write may already have committed elsewhere.
            let isCreate: Bool
            if case .create = write { isCreate = true } else { isCreate = false }
            if !uncertainAttempt, let rejection = error as? APIError,
               [400, 401, 403, 404, 413, 422, 503].contains(rejection.status) || (isCreate && rejection.status == 409) {
                control.rejectWrite()
                if rejection.status == 503 { capabilities = nil }
                message = rejection.status == 503 ? "代玩服务暂未就绪，本局已暂停，可稍后重试" : "本次交接被拒绝，本局已暂停，请确认状态后重试"
                try? await persist()
                return
            }
            uncertainAttempt = true; failureCount += 1; control.markUncertain()
            message = "交接结果待确认，请重试查询；本局暂不恢复输入"
            try? await persist()
            if let error = error as? APIError, error.status == 409, active { await resolveConflict(write, epoch: epoch, token: token) }
            return
        }
        guard epoch == scopeEpoch, token == control.generation else { return }
        do {
            try control.receive(result, generation: token)
            isReady = true; failureCount = 0; message = nil
            if control.pending == nil { uncertainAttempt = false; localSnapshot = nil }
            try await persist()
        } catch { if epoch == scopeEpoch { message = "云端已回应，本机恢复记录仍待确认" } }
    }
    public func recoverPending() async {
        guard !recovering, let write = control.pending, let api else { return }
        recovering = true; let epoch = scopeEpoch; let token = control.generation
        defer { if epoch == scopeEpoch { recovering = false } }
        do {
            let result = try await api.tetrisOperation(requestID: write.requestID)
            guard epoch == scopeEpoch, token == control.generation else { return }
            try control.receive(result, generation: token); isReady = true; failureCount = 0; message = nil
            if control.pending == nil { uncertainAttempt = false; localSnapshot = nil }
            try await persist()
        } catch let error as APIError where error.status == 404 {
            guard epoch == scopeEpoch, token == control.generation else { return }
            // A missing operation is not proof that the original POST never arrived.
            // Re-send exactly the same durable request; never invent another ID.
            await submit(write, epoch: epoch, token: token)
        } catch {
            guard epoch == scopeEpoch, token == control.generation else { return }
            control.markUncertain(); failureCount += 1; isReady = true; message = "暂时无法确认交接，可稍后重试或另开本地局"
        }
    }
    private func resolveConflict(_ write: TetrisWrite, epoch: UInt64, token: UInt64) async {
        guard let api else { return }
        do {
            let result = try await api.tetrisOperation(requestID: write.requestID)
            guard epoch == scopeEpoch, token == control.generation else { return }
            try control.receive(result, generation: token); try await persist()
        } catch let error as APIError where error.status == 404 {
            // A monotonic newer version proves that this stale command cannot commit later.
            guard case .command(let id, let request) = write,
                  let latest = try? await api.tetrisSession(id: id, afterVersion: nil, afterEventSequence: nil),
                  latest.version > request.expectedVersion,
                  epoch == scopeEpoch, token == control.generation else { return }
            do {
                control.rejectWrite(); control.markUncertain()
                try control.receive(latest, generation: token); uncertainAttempt = false; localSnapshot = nil
                try await persist(); message = "云端状态已更新，请重新选择操作"
            } catch { message = "云端状态仍待确认" }
        } catch { /* Keep the original pending operation frozen. */ }
    }
    private func loadAuthority(epoch: UInt64) async {
        guard let api, epoch == scopeEpoch else { return }
        let token = control.generation
        do {
            let latest: TetrisRemoteSession?
            if let remote { latest = try await api.tetrisSession(id: remote.id, afterVersion: remote.version, afterEventSequence: remote.eventCursor) }
            else { latest = try await api.currentTetrisSession() }
            guard epoch == scopeEpoch, token == control.generation else { return }
            if let latest {
                let keepLocal = localSnapshot != nil && remote?.id == latest.id && remote?.version == latest.version && latest.controller == .player
                try control.receive(latest, generation: token)
                if !keepLocal { localSnapshot = nil }
                if didBeginLocal && phase != .returned { control.startSeparateLocalRound() }
                if let operationID = latest.pendingOperation {
                    let operation = try await api.tetrisOperation(requestID: operationID)
                    guard epoch == scopeEpoch, token == control.generation else { return }
                    try control.receive(operation.session, generation: token)
                    if operation.status == .pending { control.markUncertain() }
                }
                try await persist()
            }
            isReady = true; failureCount = 0
        } catch {
            guard epoch == scopeEpoch, token == control.generation else { return }
            if remote != nil { control.markUncertain() }
            isReady = true; failureCount += 1; message = remote == nil ? "代玩服务暂不可用，本地游戏不受影响" : "云端状态待确认，本局暂不恢复输入"
        }
    }
    public func refresh() async {
        guard !refreshing else { return }
        refreshing = true; let epoch = scopeEpoch
        defer { if epoch == scopeEpoch { refreshing = false } }
        if control.pending != nil { await recoverPending() }
        else { await loadAuthority(epoch: epoch) }
        if epoch == scopeEpoch, let api, active {
            do {
                let latest = try await api.tetrisCapabilities()
                guard epoch == scopeEpoch else { return }
                capabilities = latest
            } catch { if epoch == scopeEpoch { capabilities = nil } }
        }
    }
    public func pauseForPanel() async -> Bool {
        if control.pending != nil { return false }
        if remote?.controller == .bot && remote?.runState != .over && !control.viewingSeparateLocal {
            if phase == .botPaused { return true }
            guard canCommand else { return false }
            await pauseBot()
            return phase == .botPaused && control.pending == nil
        }
        return true
    }
    private func startPolling(immediate: Bool = false) {
        pollTask?.cancel(); pollTask = nil
        guard automaticallyPoll, active, control.pending != nil || remote != nil else { return }
        pollTask = Task { [weak self] in
            var first = immediate
            while !Task.isCancelled {
                guard let delay = self?.pollDelay, self?.active == true else { return }
                if !first { do { try await Task.sleep(for: delay) } catch { return } }
                first = false
                guard !Task.isCancelled, let self, self.active else { return }
                if (self.phase == .returned || self.phase == .ended) && self.control.pending == nil { return }
                await self.refresh()
            }
        }
    }
    private var pollDelay: Duration {
        if failureCount > 0 { return .seconds(min(10, 1 << min(failureCount, 3))) }
        return remote?.runState == .paused && control.pending == nil ? .seconds(2) : .milliseconds(250)
    }
}
