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

    @Test func normalModeUsesTheWholePaletteAndKeepsEachAppearanceColorStable() {
        var observed = Set<String>()
        var random = Random()
        for _ in 0..<6 {
            var game = WhackABotGame()
            game.start()
            var previous: [Int: String] = [:]
            for _ in 0..<600 {
                game.advance(milliseconds: 100, using: &random)
                for target in game.targets {
                    observed.insert(target.color.hex)
                    if let oldColor = previous[target.id] { #expect(oldColor == target.color.hex) }
                    previous[target.id] = target.color.hex
                }
            }
        }
        #expect(observed == Set(BotAvatarColorPalette.all.map(\.hex)))
    }

    @Test func hardModeHoleColorsStayFixedAcrossTimeAndPause() {
        var random = Random()
        var game = WhackABotGame(mode: .hard, using: &random)
        let colors = game.holeColors
        #expect(colors.count == 9)
        #expect(colors.allSatisfy { BotAvatarColorPalette.all.contains($0) })
        game.start()
        game.advance(milliseconds: 20_500, using: &random)
        game.pause()
        game.advance(milliseconds: 10_000, using: &random)
        #expect(game.holeColors == colors)
        #expect(game.elapsedMilliseconds == 20_500)
        game.start()
        game.advance(milliseconds: 10_000, using: &random)
        #expect(game.holeColors == colors)
    }

    private func findTarget(_ game: inout WhackABotGame, matching: Bool, random: inout Random) throws -> WhackABotGame.Target {
        while game.phase == .running {
            if let target = game.targets.first(where: {
                !$0.isHit && ($0.color == game.holeColors[$0.hole]) == matching
            }) { return target }
            game.advance(milliseconds: 50, using: &random)
        }
        throw MissingTarget()
    }
    private struct MissingTarget: Error {}

    @Test func hardModeScoresMatchesAndPenalizesEachWrongAppearanceOnceWithZeroFloor() throws {
        var random = Random()
        var game = WhackABotGame(mode: .hard, using: &random)
        game.start()
        let good = try findTarget(&game, matching: true, random: &random)
        let hit = game.tap(hole: good.hole, targetID: good.id)
        #expect(hit)
        #expect(game.score == 10)
        #expect(game.hits == 1)
        let bad = try findTarget(&game, matching: false, random: &random)
        let wrong = game.tap(hole: bad.hole, targetID: bad.id)
        #expect(!wrong)
        #expect(game.score == 0)
        #expect(game.wrongColorHits == 1)
        #expect(game.targets.first { $0.id == bad.id }?.pointsAwarded == -10)
        let repeatWrong = game.tap(hole: bad.hole, targetID: bad.id)
        #expect(!repeatWrong)
        #expect(game.wrongColorHits == 1)
        let anotherBad = try findTarget(&game, matching: false, random: &random)
        let secondWrong = game.tap(hole: anotherBad.hole, targetID: anotherBad.id)
        #expect(!secondWrong)
        #expect(game.wrongColorHits == 2)
        #expect(game.score == 0)
        #expect(game.hits == 1)
        #expect(game.taps == 4)
        #expect(game.accuracyPercent == 25)
    }

    @Test func hardModeEmptyAndStaleTapsDoNotPenalize() throws {
        var random = Random()
        var game = WhackABotGame(mode: .hard, using: &random)
        game.start()
        let good = try findTarget(&game, matching: true, random: &random)
        let hit = game.tap(hole: good.hole, targetID: good.id)
        #expect(hit)
        let empty = try #require((0..<9).first { hole in !game.targets.contains { $0.hole == hole } })
        let emptyTap = game.tap(hole: empty, targetID: nil)
        #expect(!emptyTap)
        let bad = try findTarget(&game, matching: false, random: &random)
        let stale = game.tap(hole: bad.hole, targetID: good.id)
        #expect(!stale)
        #expect(game.score == 10)
        #expect(game.wrongColorHits == 0)
        game.pause()
        let pausedTap = game.tap(hole: bad.hole, targetID: bad.id)
        #expect(!pausedTap)
        #expect(game.taps == 3)
    }

    @Test func normalModeStillAwardsEveryColorWithoutPenalties() throws {
        var random = Random()
        var game = WhackABotGame(mode: .normal, using: &random)
        game.start()
        var colors = Set<String>()
        while game.phase == .running {
            game.advance(milliseconds: 50, using: &random)
            for target in game.targets where !target.isHit {
                colors.insert(target.color.hex)
                let accepted = game.tap(hole: target.hole, targetID: target.id)
                #expect(accepted)
            }
        }
        #expect(colors.count > 3)
        #expect(game.score == game.hits * 10)
        #expect(game.wrongColorHits == 0)
        #expect(game.accuracyPercent == 100)
    }

    @Test func hardModeDelayedFramesPreserveColorsAndSchedule() {
        var randomA = Random()
        var randomB = Random()
        var a = WhackABotGame(mode: .hard, using: &randomA)
        var b = WhackABotGame(mode: .hard, using: &randomB)
        a.start(); b.start()
        a.advance(milliseconds: 48_700, using: &randomA)
        for _ in 0..<487 { b.advance(milliseconds: 100, using: &randomB) }
        #expect(a.targets == b.targets)
        #expect(a.holeColors == b.holeColors)
    }

}
