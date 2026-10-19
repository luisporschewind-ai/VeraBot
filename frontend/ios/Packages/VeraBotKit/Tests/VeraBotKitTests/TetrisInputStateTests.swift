import Testing
@testable import VeraBotCore

@Suite struct TetrisInputStateTests {
    @Test func initialPressDelayedRepeatAndRelease() {
        var input = TetrisInputState()
        let result1 = input.press(.moveLeft, atMilliseconds: 0) == [.moveLeft]
        #expect(result1)
        let result2 = input.advance(toMilliseconds: 179).isEmpty
        #expect(result2)
        let result3 = input.advance(toMilliseconds: 180) == [.moveLeft]
        #expect(result3)
        let result4 = input.advance(toMilliseconds: 250) == [.moveLeft]
        #expect(result4)
        input.release(.moveLeft)
        let result5 = input.advance(toMilliseconds: 500).isEmpty
        #expect(result5)
    }
    @Test func cancellationCannotReplayOldInputAfterPause() {
        var input = TetrisInputState()
        _ = input.press(.moveRight, atMilliseconds: 0)
        input.cancel()
        let result6 = input.advance(toMilliseconds: 500).isEmpty
        #expect(result6)
        let result7 = input.press(.moveRight, atMilliseconds: 501) == [.moveRight]
        #expect(result7)
        let result8 = input.advance(toMilliseconds: 680).isEmpty
        #expect(result8)
    }
    @Test func latestDirectionWinsWithoutRestoringReleasedDirection() {
        var input = TetrisInputState()
        _ = input.press(.moveLeft, atMilliseconds: 0)
        let result9 = input.press(.moveRight, atMilliseconds: 10) == [.moveRight]
        #expect(result9)
        input.release(.moveLeft)
        let result10 = input.advance(toMilliseconds: 190) == [.moveRight]
        #expect(result10)
        input.release(.moveRight)
        let result11 = input.advance(toMilliseconds: 400).isEmpty
        #expect(result11)
    }
    @Test func jitterNeverQueuesABurstAndDuplicatePressIsIgnored() {
        var input = TetrisInputState()
        _ = input.press(.softDrop, atMilliseconds: 0)
        let result12 = input.press(.softDrop, atMilliseconds: 50).isEmpty
        #expect(result12)
        let result13 = input.advance(toMilliseconds: 2000) == [.softDrop]
        #expect(result13)
        let result14 = input.advance(toMilliseconds: 2000).isEmpty
        #expect(result14)
        let result15 = input.advance(toMilliseconds: 1990).isEmpty
        #expect(result15)
        let result16 = input.advance(toMilliseconds: 2070) == [.softDrop]
        #expect(result16)
    }
    @Test func faceButtonsNeverEnterRepeatState() {
        var input = TetrisInputState()
        let result17 = input.press(.hardDrop, atMilliseconds: 0).isEmpty
        #expect(result17)
        let result18 = input.press(.rotateClockwise, atMilliseconds: 0).isEmpty
        #expect(result18)
        let result19 = input.advance(toMilliseconds: 1000).isEmpty
        #expect(result19)
    }
    @Test func oldCountdownCannotResumeNewRound() {
        var countdown = TetrisCountdownState()
        let old = countdown.start()
        countdown.cancel()
        let result20 = !countdown.tick(generation: old)
        #expect(result20)
        let current = countdown.start()
        #expect(countdown.remaining == 3)
        let result21 = !countdown.tick(generation: current)
        #expect(result21)
        #expect(countdown.remaining == 2)
        let result22 = !countdown.tick(generation: current)
        #expect(result22)
        let result23 = countdown.tick(generation: current)
        #expect(result23)
        let result24 = !countdown.tick(generation: current)
        #expect(result24)
    }
}
