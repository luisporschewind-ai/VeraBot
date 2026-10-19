import Foundation

public enum TetrisKind: Int, CaseIterable, Codable, Sendable {
    case cyan = 1, blue, orange, yellow, green, purple, red

    public func cells(rotation: Int) -> [TetrisCell] {
        let pairs: [(Int, Int)]
        switch self {
        case .cyan: pairs = [(0,1),(1,1),(2,1),(3,1)]
        case .blue: pairs = [(0,0),(0,1),(1,1),(2,1)]
        case .orange: pairs = [(2,0),(0,1),(1,1),(2,1)]
        case .yellow: pairs = [(1,0),(2,0),(1,1),(2,1)]
        case .green: pairs = [(1,0),(2,0),(0,1),(1,1)]
        case .purple: pairs = [(1,0),(0,1),(1,1),(2,1)]
        case .red: pairs = [(0,0),(1,0),(1,1),(2,1)]
        }
        return (0..<rotation).reduce(pairs.map { TetrisCell(column: $0.0, row: $0.1) }) { cells, _ in
            cells.map { TetrisCell(column: 3 - $0.row, row: $0.column) }
        }
    }
}

public struct TetrisCell: Hashable, Codable, Sendable {
    public let column: Int
    public let row: Int
    public init(column: Int, row: Int) { self.column = column; self.row = row }
}

public struct TetrisPiece: Codable, Equatable, Sendable {
    public var kind: TetrisKind
    public var rotation: Int
    public var x: Int
    public var y: Int
    public init(kind: TetrisKind, rotation: Int = 0, x: Int = 3, y: Int = 0) {
        self.kind = kind; self.rotation = rotation; self.x = x; self.y = y
    }
}

public enum TetrisPhase: String, Codable, Sendable { case ready, running, clearing, paused, over }
public enum TetrisAction: String, Codable, Sendable {
    case start, pause, resume, moveLeft, moveRight, softDrop, rotateClockwise, hardDrop
}
public enum TetrisEventKind: String, Codable, Sendable {
    case moved, rotated, locked, linesCleared, spawned, paused, resumed, ended
}
public struct TetrisEvent: Codable, Equatable, Sendable {
    public let sequence: Int64
    public let kind: TetrisEventKind
    public let count: Int
    public let fromHardDrop: Bool
}

public struct TetrisState: Codable, Equatable, Sendable {
    public var ruleVersion = "legacy-1"
    public var board = [Int](repeating: 0, count: 200)
    public var active: TetrisPiece?
    public var next: TetrisKind = .yellow
    public var bag: [TetrisKind] = []
    public var rngState: UInt32
    public var score = 0
    public var lines = 0
    public var lockedPieces = 0
    public var phase: TetrisPhase = .running
    public var resumePhase: TetrisPhase?
    public var logicalTimeMs = 0
    public var stepRemainderMs = 0
    public var gravityRemainingMs = 620
    public var lockRemainingMs = 500
    public var lockResetCount = 0
    public var clearRemainingMs = 0
    public var pendingClearRows: [Int] = []
    public var eventSequence: Int64 = 0
    public var endReason: String?

    public init(seed: UInt32) { rngState = seed == 0 ? 0x6D2B79F5 : seed }
}

public enum TetrisStateError: Error { case invalidSnapshot }

/// Deterministic rules without UI, clocks, network calls, or model dependencies.
public struct TetrisGame: Sendable {
    public static let width = 10
    public static let height = 20
    public private(set) var state: TetrisState
    private var emitted: [TetrisEvent] = []
    private var sounds: [GameSoundEvent] = []

    public init(seed: UInt32 = UInt32.random(in: 1...UInt32.max), ruleVersion: String = "legacy-1") {
        precondition(ruleVersion == "legacy-1" || ruleVersion == TetrisRules.version)
        state = TetrisState(seed: seed)
        state.ruleVersion = ruleVersion
        state.phase = ruleVersion == TetrisRules.version ? .ready : .running
        state.active = TetrisPiece(kind: draw())
        state.next = draw()
    }

    public init(restoring state: TetrisState) throws {
        self.state = state
        try validateSnapshot()
    }

    private var isV2: Bool { state.ruleVersion == TetrisRules.version }

    private func validateSnapshot() throws {
        guard state.ruleVersion == "legacy-1" || isV2, state.board.count == 200,
              state.board.allSatisfy({ (0...7).contains($0) }), state.rngState != 0,
              (0...10_000_000).contains(state.score), (0...100_000).contains(state.lines), state.lockedPieces >= 0,
              (0...9_000_000_000_000_000).contains(state.eventSequence),
              (0...31_536_000_000).contains(state.logicalTimeMs),
              (0..<10).contains(state.stepRemainderMs), (0...500).contains(state.lockRemainingMs),
              (0...15).contains(state.lockResetCount), state.bag.count <= 7,
              Set(state.bag).count == state.bag.count,
              state.gravityRemainingMs > 0, state.gravityRemainingMs <= dropInterval,
              isV2 || [.running, .paused, .over].contains(state.phase) else { throw TetrisStateError.invalidSnapshot }
        if let active = state.active {
            guard (0...3).contains(active.rotation), (-4...19).contains(active.y),
                  (-4...9).contains(active.x) else { throw TetrisStateError.invalidSnapshot }
        }
        if state.phase == .paused {
            guard state.resumePhase == .running || (isV2 && state.resumePhase == .clearing) else { throw TetrisStateError.invalidSnapshot }
        } else if state.resumePhase != nil { throw TetrisStateError.invalidSnapshot }
        let clearing = state.phase == .clearing || (state.phase == .paused && state.resumePhase == .clearing)
        if clearing {
            guard isV2, state.active == nil, (1...180).contains(state.clearRemainingMs),
                  (1...4).contains(state.pendingClearRows.count),
                  state.pendingClearRows == fullRows else { throw TetrisStateError.invalidSnapshot }
        } else if state.phase != .over {
            guard state.clearRemainingMs == 0, state.pendingClearRows.isEmpty, fullRows.isEmpty,
                  let active = state.active, (0...3).contains(active.rotation),
                  (-4...19).contains(active.y), (-4...9).contains(active.x), fits(active) else { throw TetrisStateError.invalidSnapshot }
        }
    }

    public var dropInterval: Int { max(130, 620 - (state.lines / 10) * 55) }
    public var board: [[TetrisKind?]] {
        (0..<20).map { row in (0..<10).map { TetrisKind(rawValue: state.board[row * 10 + $0]) } }
    }
    public var activeKind: TetrisKind { state.active?.kind ?? state.next }
    public var nextKind: TetrisKind { state.next }
    public var activeCells: [TetrisCell] { cells(state.active) }
    public var score: Int { state.score }
    public var lines: Int { state.lines }
    public var lockedPieces: Int { state.lockedPieces }
    public var isPaused: Bool { state.phase == .paused }
    public var isGameOver: Bool { state.phase == .over }
    public var soundTick: Int64 { state.eventSequence }

    public var ghostCells: [TetrisCell] {
        guard var piece = state.active else { return [] }
        while fits(TetrisPiece(kind: piece.kind, rotation: piece.rotation, x: piece.x, y: piece.y + 1)) { piece.y += 1 }
        return cells(piece)
    }

    @discardableResult public mutating func apply(_ action: TetrisAction) -> [TetrisEvent] {
        emitted = []
        if action == .pause, state.phase == .running || state.phase == .clearing {
            state.resumePhase = state.phase; state.phase = .paused; emit(.paused)
            return emitted
        }
        if action == .resume, state.phase == .paused {
            state.phase = state.resumePhase ?? .running; state.resumePhase = nil; emit(.resumed)
            return emitted
        }
        if action == .start, state.phase == .ready { state.phase = .running; emit(.resumed); return emitted }
        guard state.phase == .running, var piece = state.active else { return [] }
        let wasGrounded = grounded(piece)
        switch action {
        case .moveLeft, .moveRight:
            piece.x += action == .moveLeft ? -1 : 1
            if fits(piece) { state.active = piece; resetGroundDelay(wasGrounded); emit(.moved) }
        case .rotateClockwise:
            if isV2 && piece.kind == .yellow { return [] }
            piece.rotation = (piece.rotation + 1) % 4
            let offsets = isV2 ? TetrisRules.kicks : [0, -1, 1, -2, 2].map { ($0, 0) }
            for offset in offsets {
                var candidate = piece; candidate.x += offset.0; candidate.y += offset.1
                if fits(candidate) { state.active = candidate; resetGroundDelay(wasGrounded); emit(.rotated); break }
            }
        case .softDrop:
            piece.y += 1
            if fits(piece) { state.active = piece; state.score += 1; emit(.moved) }
            else if !isV2 { lockPiece(fromHardDrop: false) }
        case .hardDrop:
            var distance = 0
            while fits(TetrisPiece(kind: piece.kind, rotation: piece.rotation, x: piece.x, y: piece.y + 1)) {
                piece.y += 1; distance += 1
            }
            state.active = piece; state.score += distance * 2
            lockPiece(fromHardDrop: true)
        default: break
        }
        return emitted
    }

    @discardableResult public mutating func advance(milliseconds: Int) -> [TetrisEvent] {
        guard milliseconds > 0 else { return [] }
        if !isV2 { return advanceLegacy(milliseconds: milliseconds) }
        guard state.phase == .running || state.phase == .clearing else { return [] }
        emitted = []
        state.stepRemainderMs += milliseconds
        while state.stepRemainderMs >= 10, state.phase == .running || state.phase == .clearing {
            state.stepRemainderMs -= 10
            state.logicalTimeMs += 10
            if state.phase == .clearing {
                state.clearRemainingMs -= 10
                if state.clearRemainingMs <= 0 {
                    resolveClear(state.pendingClearRows)
                    spawnNext()
                }
                continue
            }
            let wasGrounded = state.active.map { grounded($0) } ?? false
            state.gravityRemainingMs -= 10
            if state.gravityRemainingMs <= 0 {
                state.gravityRemainingMs = dropInterval
                if var piece = state.active {
                    piece.y += 1
                    if fits(piece) { state.active = piece; emit(.moved) }
                }
            }
            if let piece = state.active, wasGrounded && grounded(piece) {
                state.lockRemainingMs -= 10
                if state.lockRemainingMs <= 0 { lockPiece(fromHardDrop: false) }
            }
        }
        if state.phase == .over { state.stepRemainderMs = 0 }
        return emitted
    }

    private mutating func advanceLegacy(milliseconds: Int) -> [TetrisEvent] {
        guard state.phase == .running, milliseconds > 0 else { return [] }
        emitted = []
        var remaining = milliseconds
        while remaining > 0, state.phase == .running {
            let step = min(remaining, state.gravityRemainingMs)
            state.logicalTimeMs += step; state.gravityRemainingMs -= step; remaining -= step
            if state.gravityRemainingMs == 0 {
                state.gravityRemainingMs = dropInterval
                if var piece = state.active {
                    piece.y += 1
                    if fits(piece) { state.active = piece; emit(.moved) }
                    else { lockPiece(fromHardDrop: false) }
                }
            }
        }
        return emitted
    }

    @discardableResult public mutating func move(_ direction: Int) -> [TetrisEvent] { apply(direction < 0 ? .moveLeft : .moveRight) }
    @discardableResult public mutating func rotate() -> [TetrisEvent] { apply(.rotateClockwise) }
    @discardableResult public mutating func softDrop() -> [TetrisEvent] { apply(.softDrop) }
    @discardableResult public mutating func hardDrop() -> [TetrisEvent] { apply(.hardDrop) }
    @discardableResult public mutating func dropOne() -> [TetrisEvent] { advance(milliseconds: state.gravityRemainingMs) }
    public mutating func drainSounds() -> [GameSoundEvent] { defer { sounds.removeAll() }; return sounds }

    private func cells(_ piece: TetrisPiece?) -> [TetrisCell] {
        guard let piece else { return [] }
        return TetrisRules.cells(kind: piece.kind, rotation: piece.rotation, version: state.ruleVersion)
            .map { .init(column: piece.x + $0.column, row: piece.y + $0.row) }
    }
    private func fits(_ piece: TetrisPiece) -> Bool {
        guard piece.y >= -4 else { return false }
        return cells(piece).allSatisfy { cell in
            cell.column >= 0 && cell.column < 10 && cell.row < 20 &&
                (cell.row < 0 || state.board[cell.row * 10 + cell.column] == 0)
        }
    }
    private mutating func draw() -> TetrisKind {
        TetrisRules.draw(&state)
    }
    private func grounded(_ piece: TetrisPiece) -> Bool {
        !fits(TetrisPiece(kind: piece.kind, rotation: piece.rotation, x: piece.x, y: piece.y + 1))
    }
    private mutating func resetGroundDelay(_ wasGrounded: Bool) {
        if isV2, wasGrounded, state.lockResetCount < 15 {
            state.lockResetCount += 1; state.lockRemainingMs = 500
        }
    }
    private var fullRows: [Int] {
        (0..<20).filter { !state.board[$0 * 10..<($0 + 1) * 10].contains(0) }
    }
    private mutating func emit(_ kind: TetrisEventKind, count: Int = 0, fromHardDrop: Bool = false) {
        state.eventSequence += 1
        emitted.append(.init(sequence: state.eventSequence, kind: kind, count: count, fromHardDrop: fromHardDrop))
    }
    private mutating func end(_ reason: String) {
        state.phase = .over; state.resumePhase = nil; state.endReason = reason; emit(.ended); sounds.append(.gameOver)
    }
    private mutating func lockPiece(fromHardDrop: Bool) {
        let occupied = activeCells
        guard occupied.allSatisfy({ $0.row >= 0 }) else { end("topOut"); return }
        for cell in occupied { state.board[cell.row * 10 + cell.column] = activeKind.rawValue }
        state.lockedPieces += 1; emit(.locked, fromHardDrop: fromHardDrop)
        if fromHardDrop { sounds.append(.hardDrop) }
        let rows = fullRows
        if isV2 && !rows.isEmpty {
            state.pendingClearRows = rows; state.clearRemainingMs = 180
            state.phase = .clearing; state.active = nil
            return
        }
        resolveClear(rows)
        spawnNext()
    }
    private mutating func resolveClear(_ rows: [Int]) {
        let count = rows.count
        guard count > 0 else { return }
        var remaining: [[Int]] = []
        for row in 0..<20 {
            let values = Array(state.board[row * 10..<(row + 1) * 10])
            if !rows.contains(row) { remaining.append(values) }
        }
        state.board = [Int](repeating: 0, count: count * 10) + remaining.flatMap { $0 }
        state.lines += count; state.score += [0, 100, 300, 500, 800][count]
        emit(.linesCleared, count: count); sounds.append(count == 1 ? .clearSingle : .clearMulti)
    }
    private mutating func spawnNext() {
        state.active = TetrisPiece(kind: state.next); state.next = draw()
        state.phase = .running; state.resumePhase = nil
        state.pendingClearRows = []; state.clearRemainingMs = 0
        state.lockRemainingMs = 500; state.lockResetCount = 0
        state.gravityRemainingMs = dropInterval
        emit(.spawned)
        if let piece = state.active, !fits(piece) { end("blockedSpawn") }
    }
}
