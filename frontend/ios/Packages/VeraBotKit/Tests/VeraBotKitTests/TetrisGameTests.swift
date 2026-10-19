import Testing
@testable import VeraBotCore

@Suite struct TetrisGameTests {
    @Test func hardDropScoresDistanceAndLocksExactlyOnce() throws {
        var state = TetrisGame(seed: 7).state
        state.active = .init(kind: .yellow, rotation: 0, x: 3, y: 0)
        state.next = .blue
        var game = try TetrisGame(restoring: state)
        let events = game.apply(.hardDrop)
        #expect(game.state.score == 36)
        #expect(game.state.lockedPieces == 1)
        #expect(events.filter { $0.kind == .locked }.count == 1)
        #expect(events.filter { $0.kind == .spawned }.count == 1)
        #expect(game.state.active?.kind == .blue)
    }

    @Test func fourLinesScoreEightHundredPlusHardDrop() throws {
        var state = TetrisGame(seed: 7).state
        for row in 16..<20 {
            for column in 0..<10 where column != 4 { state.board[row * 10 + column] = 4 }
        }
        state.active = .init(kind: .cyan, rotation: 1, x: 2, y: 0)
        var game = try TetrisGame(restoring: state)
        let events = game.apply(.hardDrop)
        #expect(game.state.lines == 4)
        #expect(game.state.score == 832)
        #expect(game.state.board.allSatisfy { $0 == 0 })
        #expect(events.filter { $0.kind == .linesCleared }.map(\.count) == [4])
    }

    @Test func pausedGameNeverConsumesTimeOrMoves() {
        var game = TetrisGame(seed: 7)
        game.apply(.pause)
        let before = game.state
        #expect(game.advance(milliseconds: 1200).isEmpty)
        #expect(game.apply(.moveLeft).isEmpty)
        #expect(game.apply(.hardDrop).isEmpty)
        #expect(game.state == before)
    }

    @Test func blockedSpawnEndsWithoutResuming() throws {
        var state = TetrisGame(seed: 7).state
        state.active = .init(kind: .cyan, rotation: 0, x: 3, y: 10)
        state.next = .yellow
        state.board[4] = 2
        var game = try TetrisGame(restoring: state)
        let events = game.apply(.hardDrop)
        #expect(game.state.phase == .over)
        #expect(events.filter { $0.kind == .ended }.count == 1)
        #expect(game.apply(.resume).isEmpty)
        #expect(game.state.phase == .over)
    }

    @Test func invalidSnapshotRejectedBeforeRestoring() {
        var state = TetrisGame(seed: 7).state
        state.board.removeLast()
        #expect(throws: TetrisStateError.self) { try TetrisGame(restoring: state) }
    }
    @Test func runningSnapshotCannotContainUnsettledFullRows() {
        var state = TetrisGame(seed: 7).state
        for column in 0..<10 { state.board[190 + column] = 4 }
        #expect(throws: TetrisStateError.self) { try TetrisGame(restoring: state) }
    }

    @Test func pausedSnapshotCannotResumeIntoTerminalPhase() {
        var state = TetrisGame(seed: 7).state
        state.phase = .paused
        state.resumePhase = .over
        #expect(throws: TetrisStateError.self) { try TetrisGame(restoring: state) }
    }

}
