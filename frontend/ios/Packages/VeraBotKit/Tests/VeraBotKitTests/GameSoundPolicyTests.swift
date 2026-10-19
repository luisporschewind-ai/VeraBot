import Testing
@testable import VeraBotCore

@Suite struct GameSoundPolicyTests {
    @Test func keyThrottleHasExactBoundary() {
        var p = GameSoundPolicy()
        p.setActive(true)
        #expect(p.request(.keyPress, id: 1, nowMs: 0).containsPlay)
        #expect(p.request(.keyPress, id: 2, nowMs: 79).isEmpty)
        #expect(p.request(.keyPress, id: 3, nowMs: 80).containsPlay)
    }
    @Test func IDsCannotReplayAndNewSessionCanRestartSequence() {
        var p = GameSoundPolicy()
        p.setActive(true)
        #expect(p.request(.eat, id: 10, nowMs: 0).containsPlay)
        #expect(p.request(.eat, id: 10, nowMs: 100).isEmpty)
        #expect(p.request(.eat, id: 9, nowMs: 200).isEmpty)
        p.reset()
        #expect(p.request(.eat, id: 1, nowMs: 300).containsPlay)
    }
    @Test func globalFourVoicesAndTerminalPriority() {
        var p = GameSoundPolicy()
        p.setActive(true)
        for id in 1...4 { #expect(p.request(.win, id: Int64(id), nowMs: 0).containsPlay) }
        #expect(p.voiceCount == 4)
        #expect(p.request(.keyPress, id: 5, nowMs: 0).isEmpty)
        let end = p.request(.gameOver, id: 6, nowMs: 0)
        #expect(end.containsPlay && end.containsStop && p.voiceCount == 4)
    }
    @Test func clearReplacesUnfinishedHardDrop() {
        var p = GameSoundPolicy()
        p.setActive(true)
        let first = p.request(.hardDrop, id: 1, nowMs: 0)
        let clear = p.request(.clearMulti, id: 2, nowMs: 0)
        #expect(first.containsPlay && clear.containsPlay && clear.containsStop)
        #expect(p.voiceCount == 1)
    }
    @Test func routeBlockSurvivesLifecycleUntilExplicitEnable() {
        var p = GameSoundPolicy()
        p.setActive(true)
        _ = p.request(.eat, id: 1, nowMs: 0)
        #expect(p.routeDisconnected() == [.stopAll])
        p.setActive(false)
        p.setActive(true)
        #expect(p.request(.eat, id: 2, nowMs: 1).isEmpty)
        p.setEnabled(true)
        #expect(p.request(.eat, id: 3, nowMs: 2).containsPlay)
        #expect(p.setEnabled(false) == [.stopAll])
        #expect(p.request(.eat, id: 4, nowMs: 3).isEmpty)
    }
    @Test func oldVoiceCompletionCannotClearNewVoice() {
        var p = GameSoundPolicy()
        p.setActive(true)
        let old = p.request(.eat, id: 1, nowMs: 0).voice!
        p.reset()
        _ = p.request(.eat, id: 1, nowMs: 10)
        p.finished(old)
        #expect(p.voiceCount == 1)
        #expect(p.setActive(false) == [.stopAll])
        #expect(p.request(.eat, id: 2, nowMs: 20).isEmpty)
    }
}
private extension Array where Element == GameSoundCommand {
    var containsPlay: Bool { contains { if case .play = $0 { true } else { false } } }
    var containsStop: Bool { contains { if case .stopVoice = $0 { true } else { false } } }
    var voice: UInt64? { for command in self { if case let .play(id, _) = command { return id } }; return nil }
}
