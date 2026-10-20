import Testing
@testable import VeraBotCore

@Suite struct WhackABotGameTests {
    private struct Random: RandomNumberGenerator {
        var state: UInt64 = 12345
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test func onlyLiveTargetsScoreAndEachAppearanceScoresOnce() throws {
        var game = WhackABotGame()
        var random = Random()
        let tapResult1 = game.tap(hole: 0, targetID: nil)
        #expect(!tapResult1)
        #expect(game.taps == 0)
        game.start()
        game.advance(milliseconds: 1, using: &random)
        let target = try #require(game.targets.first)
        let tapResult2 = game.tap(hole: target.hole, targetID: target.id)
        #expect(tapResult2)
        let tapResult3 = game.tap(hole: target.hole, targetID: target.id)
        #expect(!tapResult3)
        let tapResult4 = game.tap(hole: (target.hole + 1) % 9, targetID: nil)
        #expect(!tapResult4)
        #expect(game.score == 10)
        #expect(game.hits == 1)
        #expect(game.taps == 3)
        #expect(game.accuracyPercent == 33)
        #expect(game.targets.first?.isHit == true)
    }

    @Test func missedBotsExpireWithoutLosingPointsAndStaleTapsCannotHitTheirReplacement() throws {
        var game = WhackABotGame()
        var random = Random()
        game.start()
        game.advance(milliseconds: 1, using: &random)
        let expired = try #require(game.targets.first)
        game.advance(milliseconds: 1_500, using: &random)
        #expect(!game.targets.contains { $0.id == expired.id })
        #expect(game.score == 0)
        game.advance(milliseconds: 300, using: &random)
        let replacement = try #require(game.targets.first)
        let tapResult5 = game.tap(hole: replacement.hole, targetID: expired.id)
        #expect(!tapResult5)
        let tapResult6 = game.tap(hole: replacement.hole, targetID: replacement.id)
        #expect(tapResult6)
        #expect(game.score == 10)
        #expect(game.accuracyPercent == 50)
    }

    @Test func pauseFreezesTimeTargetsAndInputUntilExplicitResume() throws {
        var game = WhackABotGame()
        var random = Random()
        game.start()
        game.advance(milliseconds: 700, using: &random)
        let targets = game.targets
        let target = try #require(targets.first)
        game.pause()
        game.advance(milliseconds: 60_000, using: &random)
        #expect(game.phase == .paused)
        #expect(game.elapsedMilliseconds == 700)
        #expect(game.targets == targets)
        let tapResult7 = game.tap(hole: target.hole, targetID: target.id)
        #expect(!tapResult7)
        #expect(game.taps == 0)
        game.start()
        let tapResult8 = game.tap(hole: target.hole, targetID: target.id)
        #expect(tapResult8)
        game.advance(milliseconds: 300, using: &random)
        #expect(game.elapsedMilliseconds == 1_000)
        #expect(game.remainingSeconds == 59)
    }

    @Test func roundEndsExactlyAtSixtySecondsAndRejectsLateInput() {
        var game = WhackABotGame()
        var random = Random()
        game.start()
        game.advance(milliseconds: 59_999, using: &random)
        #expect(game.phase == .running)
        #expect(game.remainingSeconds == 1)
        game.advance(milliseconds: 1, using: &random)
        #expect(game.phase == .finished)
        #expect(game.remainingSeconds == 0)
        #expect(game.targets.isEmpty)
        let tapResult9 = game.tap(hole: 0, targetID: nil)
        #expect(!tapResult9)
        game.start()
        game.advance(milliseconds: Int.max, using: &random)
        #expect(game.phase == .finished)
        #expect(game.elapsedMilliseconds == 60_000)
        #expect(game.taps == 0)
        #expect(game.accuracyPercent == 0)
    }

    @Test func laterStagesIncreaseActivityWithoutDuplicateHolesOrMoreThanThreeBots() {
        var game = WhackABotGame()
        var random = Random()
        var earlyMaximum = 0
        var middleMaximum = 0
        var lateMaximum = 0
        game.start()
        for _ in 0..<600 {
            game.advance(milliseconds: 100, using: &random)
            let count = game.targets.count
            #expect(count <= 3)
            #expect(Set(game.targets.map(\.hole)).count == count)
            #expect(game.targets.allSatisfy { (0..<9).contains($0.hole) })
            if game.elapsedMilliseconds < 20_000 { earlyMaximum = max(earlyMaximum, count) }
            else if game.elapsedMilliseconds < 40_000 { middleMaximum = max(middleMaximum, count) }
            else { lateMaximum = max(lateMaximum, count) }
        }
        #expect(earlyMaximum == 1)
        #expect(middleMaximum == 2)
        #expect(lateMaximum == 3)
    }

    @Test func delayedFramesMatchSmallStepsAndInvalidTimeDoesNothing() {
        var batched = WhackABotGame()
        var stepped = WhackABotGame()
        var randomA = Random()
        var randomB = Random()
        batched.start()
        stepped.start()
        batched.advance(milliseconds: -1, using: &randomA)
        batched.advance(milliseconds: 0, using: &randomA)
        #expect(batched.targets.isEmpty)
        batched.advance(milliseconds: 48_700, using: &randomA)
        for _ in 0..<487 { stepped.advance(milliseconds: 100, using: &randomB) }
        #expect(batched.elapsedMilliseconds == stepped.elapsedMilliseconds)
        #expect(batched.targets == stepped.targets)
    }

    @Test func hitFeedbackVanishesAndNewRoundResetsResults() throws {
        var game = WhackABotGame()
        var random = Random()
        game.start()
        game.advance(milliseconds: 1, using: &random)
        let target = try #require(game.targets.first)
        let tapResult10 = game.tap(hole: -1, targetID: target.id)
        #expect(!tapResult10)
        let tapResult11 = game.tap(hole: 9, targetID: target.id)
        #expect(!tapResult11)
        #expect(game.taps == 0)
        let tapResult12 = game.tap(hole: target.hole, targetID: target.id)
        #expect(tapResult12)
        game.advance(milliseconds: 250, using: &random)
        #expect(!game.targets.contains { $0.id == target.id })
        game = WhackABotGame()
        #expect(game.phase == .ready)
        #expect(game.score == 0)
        #expect(game.taps == 0)
        #expect(game.remainingSeconds == 60)
        #expect(game.targets.isEmpty)
    }
}
