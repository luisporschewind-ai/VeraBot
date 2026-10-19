import Testing
@testable import VeraBotCore

@Suite struct SnakeGameTests {
    private struct LastCellRandom: RandomNumberGenerator {
        mutating func next() -> UInt64 { UInt64.max }
    }

    private func game(width: Int = 20, height: Int = 20) -> SnakeGame {
        var random = LastCellRandom()
        return SnakeGame(width: width, height: height, using: &random)
    }

    private func tick(_ game: inout SnakeGame, times: Int = 1) {
        var random = LastCellRandom()
        for _ in 0..<times { game.tick(using: &random) }
    }

    @Test func inputReportsOnlyAcceptedTurnsForSwipeFeedback() {
        var g = game()
        let ready = g.turn(.up)
        g.start()
        let reverse = g.turn(.left)
        let accepted = g.turn(.up)
        let duplicate = g.turn(.up)
        #expect(ready == false)
        #expect(reverse == false)
        #expect(accepted == true)
        #expect(duplicate == false)
    }
    @Test func waitsForStartAndMovesOneCellPerTick() {
        var g = game()
        let head = g.snake[0]
        tick(&g)
        #expect(g.phase == .ready)
        #expect(g.snake[0] == head)
        g.start()
        tick(&g)
        #expect(g.phase == .running)
        #expect(g.snake[0] == SnakeGame.Cell(column: head.column + 1, row: head.row))
        #expect(g.snake.count == 4)
    }

    @Test func eatingGrowsScoresAndSpawnsOnlyOnFreeCells() {
        var g = game()
        g.start()
        tick(&g, times: 9)
        g.turn(.down)
        tick(&g, times: 9)
        #expect(g.score == 10)
        #expect(g.snake.count == 5)
        #expect(g.food != nil)
        #expect(!g.snake.contains(g.food!))
        #expect(g.snake[0] == SnakeGame.Cell(column: 19, row: 19))
    }

    @Test func cannotReverseOrTurnTwiceDuringOneTick() {
        var g = game()
        g.start()
        g.turn(.left)
        g.turn(.up)
        g.turn(.down)
        g.turn(.left)
        g.turn(.down) // The two-slot input queue is full.
        tick(&g)
        #expect(g.direction == .up)
        #expect(g.snake[0] == SnakeGame.Cell(column: 10, row: 9))
        tick(&g)
        #expect(g.direction == .left)
        #expect(g.snake[0] == SnakeGame.Cell(column: 9, row: 9))
        tick(&g)
        #expect(g.direction == .left)
    }

    @Test func movingIntoVacatingTailIsAllowed() {
        var g = game()
        g.start()
        for direction in [SnakeGame.Direction.up, .right, .down, .left] {
            g.turn(direction)
            tick(&g)
        }
        #expect(g.phase == .running)
        #expect(g.snake[0] == SnakeGame.Cell(column: 10, row: 10))
        #expect(Set(g.snake).count == g.snake.count)
    }

    @Test func wallCollisionEndsOnceWithoutMovingOutsideBoard() {
        var g = game()
        g.start()
        tick(&g, times: 10)
        #expect(g.phase == .lost)
        #expect(g.endReason == .wall)
        #expect(g.snake[0].column == 19)
        let stopped = g.snake
        tick(&g, times: 5)
        g.start()
        #expect(g.phase == .lost)
        #expect(g.snake == stopped)
    }

    @Test func bodyCollisionEndsTheRound() {
        var g = game()
        g.start()
        tick(&g, times: 9)
        g.turn(.down)
        tick(&g, times: 9)
        g.turn(.left)
        tick(&g)
        g.turn(.up)
        tick(&g)
        g.turn(.right)
        tick(&g)
        #expect(g.phase == .lost)
        #expect(g.endReason == .body)
        #expect(g.score == 20)
    }

    @Test func pauseFreezesStateAndClearsQueuedInput() {
        var g = game()
        g.start()
        g.turn(.up)
        g.pause()
        let stopped = g.snake
        g.turn(.down)
        tick(&g, times: 3)
        #expect(g.phase == .paused)
        #expect(g.snake == stopped)
        g.start()
        tick(&g)
        #expect(g.direction == .right)
        #expect(g.snake[0] == SnakeGame.Cell(column: 11, row: 10))
    }

    @Test func fillingBoardWinsWithoutSearchingForFoodForever() {
        var g = game(width: 2, height: 2)
        g.start()
        g.turn(.up)
        tick(&g)
        g.turn(.left)
        tick(&g)
        #expect(g.phase == .won)
        #expect(g.snake.count == 4)
        #expect(g.food == nil)
        #expect(g.score == 20)
        tick(&g)
        #expect(g.phase == .won)
    }

    @Test func speedIncreasesWithFoodButHasAFloor() {
        var g = game(width: 3, height: 3)
        let initialInterval = g.tickIntervalMilliseconds
        g.start()
        for direction in [SnakeGame.Direction.down, .left, .left, .up, .up, .right, .right] {
            g.turn(direction)
            tick(&g)
        }
        #expect(g.score >= 40)
        #expect(g.tickIntervalMilliseconds < initialInterval)
        #expect(g.tickIntervalMilliseconds >= 90)
    }

    @Test func newRoundStartsCleanAndFoodIsInsideBoard() {
        var g = game()
        g.start()
        tick(&g, times: 10)
        g = game()
        #expect(g.phase == .ready)
        #expect(g.score == 0)
        #expect(g.direction == .right)
        #expect(g.endReason == nil)
        #expect(!g.snake.contains(g.food!))
        #expect((0..<g.width).contains(g.food!.column))
        #expect((0..<g.height).contains(g.food!.row))
    }
}
