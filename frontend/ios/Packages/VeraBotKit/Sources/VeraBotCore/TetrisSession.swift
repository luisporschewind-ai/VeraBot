import Foundation

public enum TetrisController: String, Codable, Sendable { case player, bot }
public enum TetrisRunState: String, Codable, Sendable { case running, paused, over }
public enum TetrisCommand: String, Codable, Sendable { case handoff, pauseBot, resumeBot, reclaim, end, changeBot }
public enum TetrisOperationStatus: String, Codable, Sendable { case pending, committed }
public enum TetrisControlPhase: String, Sendable { case local, pending, botRunning, botPaused, returned, ended, recoveryRequired }
public enum TetrisSessionError: Error { case invalidContract, transitionPending }

public struct TetrisContribution: Codable, Equatable, Sendable {
    public var playerScore: Int
    public var playerLines: Int
    public var botScore: Int
    public var botLines: Int
    public init(playerScore: Int, playerLines: Int, botScore: Int, botLines: Int) {
        self.playerScore = playerScore; self.playerLines = playerLines; self.botScore = botScore; self.botLines = botLines
    }
}

public struct TetrisRemoteSession: Codable, Equatable, Sendable {
    public var id: String
    public var originClientID: String
    public var botID: Int?
    public var controller: TetrisController
    public var runState: TetrisRunState
    public var version: Int64
    public var controlEpoch: Int64
    public var latestSnapshot: TetrisState
    public var contribution: TetrisContribution
    public var updatedAt: Double
    public var pendingOperation: String?
    public var events: [TetrisEvent]
    public var eventCursor: Int64
    public var snapshotFallback: Bool
    public init(id: String, originClientID: String, botID: Int?, controller: TetrisController,
                runState: TetrisRunState, version: Int64, controlEpoch: Int64, latestSnapshot: TetrisState,
                contribution: TetrisContribution, updatedAt: Double, pendingOperation: String? = nil,
                events: [TetrisEvent] = [], eventCursor: Int64? = nil, snapshotFallback: Bool = true) {
        self.id = id; self.originClientID = originClientID; self.botID = botID; self.controller = controller
        self.runState = runState; self.version = version; self.controlEpoch = controlEpoch
        self.latestSnapshot = latestSnapshot; self.contribution = contribution; self.updatedAt = updatedAt
        self.pendingOperation = pendingOperation; self.events = events
        self.eventCursor = eventCursor ?? latestSnapshot.eventSequence; self.snapshotFallback = snapshotFallback
    }
    public func validate() throws {
        guard UUID(uuidString: id) != nil, UUID(uuidString: originClientID) != nil,
              version > 0, controlEpoch > 0, updatedAt.isFinite,
              latestSnapshot.ruleVersion == TetrisContract.ruleVersion,
              [contribution.playerScore, contribution.botScore, contribution.playerLines, contribution.botLines].allSatisfy({ (0...10_000_000).contains($0) }),
              contribution.playerScore + contribution.botScore == latestSnapshot.score,
              contribution.playerLines + contribution.botLines == latestSnapshot.lines,
              eventCursor == latestSnapshot.eventSequence, events.count <= 100,
              events.allSatisfy({ $0.sequence <= eventCursor && $0.sequence > 0 }),
              zip(events, events.dropFirst()).allSatisfy({ $0.sequence < $1.sequence }) else { throw TetrisSessionError.invalidContract }
        _ = try TetrisGame(restoring: latestSnapshot)
        if runState == .running && ![.running, .clearing].contains(latestSnapshot.phase) { throw TetrisSessionError.invalidContract }
        if runState == .paused && latestSnapshot.phase != .paused { throw TetrisSessionError.invalidContract }
        if controller == .player && runState == .running { throw TetrisSessionError.invalidContract }
    }
}

public struct TetrisCapabilities: Codable, Equatable, Sendable {
    public var available: Bool
    public var workerReady: Bool
    public var active: Int
    public var capacity: Int
    public var ruleVersion: String
    public var fixtureSHA256: String
    public init(available: Bool, workerReady: Bool, active: Int = 0, capacity: Int = 16,
                ruleVersion: String = TetrisContract.ruleVersion, fixtureSHA256: String = TetrisContract.fixtureSHA256) {
        self.available = available; self.workerReady = workerReady; self.active = active; self.capacity = capacity
        self.ruleVersion = ruleVersion; self.fixtureSHA256 = fixtureSHA256
    }
    public var compatible: Bool { ruleVersion == TetrisContract.ruleVersion && fixtureSHA256 == TetrisContract.fixtureSHA256 }
}

public struct TetrisHandoffRequest: Codable, Equatable, Sendable {
    public var requestID: String
    public var clientID: String
    public var expectedVersion: Int64 = 0
    public var expectedEpoch: Int64 = 0
    public var botID: Int
    public var snapshot: TetrisState
    public init(requestID: String = UUID().uuidString, clientID: String, botID: Int, snapshot: TetrisState) {
        self.requestID = requestID; self.clientID = clientID; self.botID = botID; self.snapshot = snapshot
    }
}
public struct TetrisCommandRequest: Codable, Equatable, Sendable {
    public var requestID: String
    public var clientID: String
    public var expectedVersion: Int64
    public var expectedEpoch: Int64
    public var command: TetrisCommand
    public var botID: Int?
    public var snapshot: TetrisState?
    public init(requestID: String = UUID().uuidString, clientID: String, expectedVersion: Int64,
                expectedEpoch: Int64, command: TetrisCommand, botID: Int? = nil, snapshot: TetrisState? = nil) {
        self.requestID = requestID; self.clientID = clientID; self.expectedVersion = expectedVersion
        self.expectedEpoch = expectedEpoch; self.command = command; self.botID = botID; self.snapshot = snapshot
    }
}
public enum TetrisWrite: Codable, Equatable, Sendable {
    case create(TetrisHandoffRequest)
    case command(sessionID: String, request: TetrisCommandRequest)
    public var requestID: String { switch self { case .create(let request): request.requestID; case .command(_, let request): request.requestID } }
    public var clientID: String { switch self { case .create(let request): request.clientID; case .command(_, let request): request.clientID } }
}
public struct TetrisOperation: Codable, Equatable, Sendable {
    public var requestID: String
    public var status: TetrisOperationStatus
    public var session: TetrisRemoteSession
    public init(requestID: String, status: TetrisOperationStatus, session: TetrisRemoteSession) {
        self.requestID = requestID; self.status = status; self.session = session
    }
}

/// This state never infers a successful handoff from a timeout or a GET snapshot.
public struct TetrisSessionControl: Sendable {
    public let clientID: String
    public private(set) var generation: UInt64 = 0
    public private(set) var phase: TetrisControlPhase = .local
    public private(set) var remote: TetrisRemoteSession?
    public private(set) var pending: TetrisWrite?
    public private(set) var viewingSeparateLocal = false
    private var priorPhase: TetrisControlPhase = .local
    public init(clientID: String) { self.clientID = clientID }
    public var canRunLocal: Bool { viewingSeparateLocal || phase == .local || (phase == .returned && remote?.originClientID == clientID) }
    public var canCommand: Bool { !viewingSeparateLocal && pending == nil && remote?.originClientID == clientID && remote?.runState != .over }
    public mutating func reset() {
        generation &+= 1; remote = nil; pending = nil; phase = .local; priorPhase = .local; viewingSeparateLocal = false
    }
    public mutating func restore(remote: TetrisRemoteSession?, pending: TetrisWrite?) throws {
        reset()
        if let remote { try receive(remote, generation: generation) }
        if let pending { _ = try begin(pending) }
    }
    @discardableResult public mutating func begin(_ write: TetrisWrite) throws -> UInt64 {
        guard pending == nil, !viewingSeparateLocal, write.clientID == clientID else { throw TetrisSessionError.transitionPending }
        priorPhase = phase; generation &+= 1; pending = write; phase = .pending
        return generation
    }
    public mutating func markUncertain() { if pending != nil { phase = .pending } else { phase = .recoveryRequired } }
    public mutating func rejectWrite() { pending = nil; phase = priorPhase }
    public mutating func startSeparateLocalRound() { viewingSeparateLocal = true }
    public mutating func watchRemote() { viewingSeparateLocal = false }
    public mutating func receive(_ session: TetrisRemoteSession, generation token: UInt64) throws {
        guard token == generation else { return }
        try session.validate()
        if let remote {
            guard session.id == remote.id || remote.runState == .over else { throw TetrisSessionError.invalidContract }
            if session.id == remote.id && session.version < remote.version { return }
        }
        remote = session
        if pending == nil { classify() }
    }
    public mutating func receive(_ result: TetrisOperation, generation token: UInt64) throws {
        guard token == generation, result.requestID == pending?.requestID else { return }
        try receive(result.session, generation: token)
        if result.status == .committed { pending = nil; classify() }
    }
    private mutating func classify() {
        guard let remote else { phase = .local; return }
        if remote.runState == .over { phase = .ended }
        else if remote.controller == .player { phase = remote.originClientID == clientID ? .returned : .recoveryRequired }
        else { phase = remote.runState == .paused ? .botPaused : .botRunning }
    }
}
