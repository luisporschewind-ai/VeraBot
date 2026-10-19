import Foundation
import Testing
@testable import VeraBotCore

@Suite struct TetrisRulesTests {
    private func running() -> TetrisGame {
        var game = TetrisGame(seed: 42, ruleVersion: "vera-tetris-2")
        game.apply(.start)
        return game
    }
    private func grounded() throws -> TetrisGame {
        var state = running().state
        state.active = .init(kind: .yellow, x: 3, y: 18)
        return try TetrisGame(restoring: state)
    }
    private func clearing() throws -> TetrisGame {
        var state = running().state
        for row in 16..<20 {
            for column in 0..<10 where column != 4 { state.board[row * 10 + column] = 4 }
        }
        state.active = .init(kind: .cyan, rotation: 1, x: 2, y: 0)
        var game = try TetrisGame(restoring: state)
        game.apply(.hardDrop)
        return game
    }
    @Test func terminalSnapshotStillValidatesPieceRanges() {
        var state = running().state
        state.phase = .over
        state.active = .init(kind: .purple, rotation: -1)
        #expect(throws: TetrisStateError.self) { try TetrisGame(restoring: state) }
        state.active = .init(kind: .purple, x: Int.max)
        #expect(throws: TetrisStateError.self) { try TetrisGame(restoring: state) }
    }
    @Test func naturalLandingStartsFullFiveHundredMillisecondDelay() throws {
        var state = running().state
        state.active = .init(kind: .yellow, x: 3, y: 17)
        state.gravityRemainingMs = 10
        var game = try TetrisGame(restoring: state)
        game.advance(milliseconds: 10)
        #expect(game.state.active?.y == 18)
        #expect(game.state.lockRemainingMs == 500)
        game.advance(milliseconds: 490)
        #expect(game.lockedPieces == 0)
        game.advance(milliseconds: 10)
        #expect(game.lockedPieces == 1)
    }
    @Test func longElapsedIsEquivalentToPartitions() {
        var first = running(), second = running()
        first.advance(milliseconds: 6000)
        second.advance(milliseconds: 5000)
        second.advance(milliseconds: 1000)
        #expect(first.state == second.state)
        #expect(first.state.logicalTimeMs == 6000)
    }
    @Test func readyWaitsForExplicitStart() {
        var game = TetrisGame(seed: 42, ruleVersion: "vera-tetris-2")
        #expect(game.state.phase == .ready)
        let before = game.state
        let events = game.advance(milliseconds: 1000)
        #expect(events.isEmpty)
        #expect(game.state == before)
        game.apply(.start)
        #expect(game.state.phase == .running)
    }
    @Test func eachOfThreeBagsContainsAllSevenKinds() throws {
        var game = running()
        var pieces: [TetrisKind] = []
        for _ in 0..<21 {
            pieces.append(game.activeKind)
            game.apply(.hardDrop)
            var state = game.state
            state.board = Array(repeating: 0, count: 200)
            game = try TetrisGame(restoring: state)
        }
        #expect(Set(pieces[0..<7]).count == 7)
        #expect(Set(pieces[7..<14]).count == 7)
        #expect(Set(pieces[14..<21]).count == 7)
    }
    @Test func elapsedPartitionsAndSubStepRemainderAreEquivalent() {
        var first = running(), second = running()
        first.advance(milliseconds: 621)
        for _ in 0..<62 { second.advance(milliseconds: 10) }
        second.advance(milliseconds: 1)
        #expect(first.state == second.state)
        #expect(first.state.stepRemainderMs == 1)
    }
    @Test func groundDelayIsExactlyFiveHundredMilliseconds() throws {
        var game = try grounded()
        game.advance(milliseconds: 490)
        #expect(game.lockedPieces == 0)
        #expect(game.state.lockRemainingMs == 10)
        game.advance(milliseconds: 10)
        #expect(game.lockedPieces == 1)
    }
    @Test func softDropOnGroundWaitsButHardDropLocksImmediately() throws {
        var game = try grounded()
        game.apply(.softDrop)
        #expect(game.lockedPieces == 0)
        game.apply(.hardDrop)
        #expect(game.lockedPieces == 1)
    }
    @Test func fifteenthSuccessfulAdjustmentIsLastDelayReset() throws {
        var game = try grounded()
        for index in 0..<15 {
            game.advance(milliseconds: 490)
            game.apply(index.isMultiple(of: 2) ? .moveLeft : .moveRight)
            #expect(game.state.lockRemainingMs == 500)
        }
        #expect(game.state.lockResetCount == 15)
        game.advance(milliseconds: 490)
        game.apply(.moveRight)
        #expect(game.state.lockRemainingMs == 10)
        game.advance(milliseconds: 10)
        #expect(game.lockedPieces == 1)
    }
    @Test func squareRotationDoesNotExtendGroundTime() throws {
        var game = try grounded()
        game.advance(milliseconds: 490)
        let events = game.apply(.rotateClockwise)
        #expect(events.isEmpty)
        #expect(game.state.lockResetCount == 0)
        game.advance(milliseconds: 10)
        #expect(game.lockedPieces == 1)
    }
    @Test func ghostUsesTheActualHardDropLanding() throws {
        var state = running().state
        state.active = .init(kind: .purple, x: 3, y: 0)
        var game = try TetrisGame(restoring: state)
        let target = game.ghostCells
        #expect(target.count == 4)
        game.apply(.hardDrop)
        for cell in target { #expect(game.state.board[cell.row * 10 + cell.column] == 6) }
    }
    @Test func pausedClearPreservesTimeAndAwardsExactlyOnce() throws {
        var game = try clearing()
        #expect(game.state.phase == .clearing)
        #expect(game.lines == 0)
        let blocked = game.apply(.moveLeft)
        #expect(blocked.isEmpty)
        game.apply(.pause)
        let paused = game.state
        game.advance(milliseconds: 1000)
        #expect(game.state == paused)
        game.apply(.resume)
        game.advance(milliseconds: 170)
        #expect(game.lines == 0)
        let events = game.advance(milliseconds: 10)
        #expect(game.lines == 4)
        #expect(game.score == 832)
        #expect(events.filter { $0.kind == .linesCleared }.map(\.count) == [4])
        game.advance(milliseconds: 100)
        #expect(game.lines == 4)
    }
    @Test func clearingSnapshotRoundTripsWithoutDiscardingTimers() throws {
        var game = try clearing()
        game.advance(milliseconds: 70)
        game.apply(.pause)
        let data = try JSONEncoder().encode(game.state)
        let snapshot = try JSONDecoder().decode(TetrisState.self, from: data)
        var restored = try TetrisGame(restoring: snapshot)
        #expect(restored.state.clearRemainingMs == 110)
        restored.apply(.resume)
        restored.advance(milliseconds: 110)
        #expect(restored.score == 832)
        #expect(restored.state.phase == .running)
    }
    @Test func topOutWritesNoPartialPiece() throws {
        var state = running().state
        state.active = .init(kind: .cyan, rotation: 1, x: 2, y: -2)
        state.board[24] = 2
        var game = try TetrisGame(restoring: state)
        game.apply(.hardDrop)
        #expect(game.state.phase == .over)
        #expect(game.state.board == state.board)
    }
    @Test func teeRotatesAroundItsThreeByThreeCenter() throws {
        var state = running().state
        state.active = .init(kind: .purple, x: 3, y: 0)
        var game = try TetrisGame(restoring: state)
        game.apply(.rotateClockwise)
        let expected: Set<TetrisCell> = [.init(column: 5, row: 1), .init(column: 4, row: 0), .init(column: 4, row: 1), .init(column: 4, row: 2)]
        #expect(Set(game.activeCells) == expected)
    }
    @Test func clockwiseWallKickStaysInBounds() throws {
        var state = running().state
        state.active = .init(kind: .purple, rotation: 1, x: -1, y: 0)
        var game = try TetrisGame(restoring: state)
        game.apply(.rotateClockwise)
        #expect(game.state.active?.x == 0)
        #expect(game.state.active?.rotation == 2)
    }
    @Test func leftKickWinsWhenBothSidesAreAvailable() throws {
        var state = running().state
        state.active = .init(kind: .purple, x: 3, y: 5)
        state.board[74] = 2
        var game = try TetrisGame(restoring: state)
        game.apply(.rotateClockwise)
        #expect(game.state.active?.x == 2)
        #expect(game.state.active?.y == 5)
    }
    @Test func blockedRotationCannotResetGroundDelay() throws {
        var state = running().state
        state.active = .init(kind: .purple, x: 3, y: 17)
        for row in 0..<20 { for column in 0..<9 { state.board[row * 10 + column] = 7 } }
        for index in [174, 183, 184, 185] { state.board[index] = 0 }
        var game = try TetrisGame(restoring: state)
        let before = game.state
        let events = game.apply(.rotateClockwise)
        #expect(events.isEmpty)
        #expect(game.state == before)
    }

}
