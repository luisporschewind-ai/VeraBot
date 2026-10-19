import Foundation
import Testing
@testable import VeraBotCore

@Suite struct TetrisCompanionUpgradeTests {
    @Test func gameplayCannotSpendTheReservedEndTurn() {
        var policy = TetrisCompanionPolicy()
        let first = policy.reserve(event: .start, at: 0)
        let second = policy.reserve(event: .highlight, at: 30)
        let extra = policy.reserve(event: .highlight, at: 60)
        let end = policy.reserve(event: .end, at: 60)
        let again = policy.reserve(event: .end, at: 90)
        #expect(first && second)
        #expect(!extra)
        #expect(end)
        #expect(!again)
    }
    @Test func cooldownDeniedEndDoesNotConsumeItsReservation() {
        var policy = TetrisCompanionPolicy()
        _ = policy.reserve(event: .start, at: 0)
        _ = policy.reserve(event: .highlight, at: 30)
        let early = policy.reserve(event: .end, at: 59)
        #expect(!early)
        #expect(policy.count == 2)
        let ready = policy.reserve(event: .end, at: 60)
        #expect(ready)
    }
    @Test func failedReservationStillCountsAndQuietDoesNotRequest() {
        var policy = TetrisCompanionPolicy()
        _ = policy.reserve(event: .start, at: 0)
        #expect(policy.count == 1)
        policy.isQuiet = true
        let silent = policy.reserve(event: .highlight, at: 30)
        #expect(!silent)
        #expect(policy.count == 1)
    }
    @Test func dangerHasHysteresisInsteadOfWarningOnEveryPiece() {
        var policy = TetrisCompanionReactionPolicy()
        let safe = policy.consume(event: .locked, height: 14)
        let danger = policy.consume(event: .locked, height: 15)
        let repeatDanger = policy.consume(event: .locked, height: 16)
        _ = policy.consume(event: .locked, height: 12)
        let returnDanger = policy.consume(event: .locked, height: 15)
        #expect(safe == nil)
        #expect(danger?.kind == .warning)
        #expect(repeatDanger == nil)
        #expect(returnDanger?.kind == .warning)
    }
    @Test func clearAndEndReactionsHaveBoundedDuration() {
        var policy = TetrisCompanionReactionPolicy()
        let single = policy.consume(event: .linesCleared, height: 5, cleared: 1)
        let multi = policy.consume(event: .linesCleared, height: 5, cleared: 4)
        let end = policy.consume(event: .ended, height: 20)
        #expect(single?.kind == .smile && single?.durationMs == 1200)
        #expect(multi?.kind == .success && multi?.durationMs == 2000)
        #expect(end?.kind == .failure && end?.durationMs == 1500)
    }
    @Test func staleRoundPartnerOrAccountCannotAcceptAResponse() {
        let round = UUID(), old = UUID()
        let token = TetrisCompanionEpoch(round: round, partner: 7, session: 9)
        #expect(token.accepts(round: round, partner: 7, session: 9))
        #expect(!token.accepts(round: old, partner: 7, session: 9))
        #expect(!token.accepts(round: round, partner: 8, session: 9))
        #expect(!token.accepts(round: round, partner: 7, session: 10))
    }
}
