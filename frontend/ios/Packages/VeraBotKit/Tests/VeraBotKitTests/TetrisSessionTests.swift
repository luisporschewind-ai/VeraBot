import Foundation
import Testing
@testable import VeraBotCore

private let origin = "00000000-0000-0000-0000-000000000001"
private let sid = "00000000-0000-0000-0000-000000000002"
private func remote(controller: TetrisController = .bot, version: Int64 = 1, epoch: Int64 = 1) -> TetrisRemoteSession {
    var game = TetrisGame(seed: 42, ruleVersion: "vera-tetris-2")
    game.apply(.start)
    if controller == .player { game.apply(.pause) }
    return TetrisRemoteSession(id: sid, originClientID: origin, botID: 7, controller: controller,
        runState: controller == .bot ? .running : .paused, version: version, controlEpoch: epoch,
        latestSnapshot: game.state, contribution: .init(playerScore: 0, playerLines: 0, botScore: 0, botLines: 0), updatedAt: 1)
}
@Suite struct TetrisSessionTests {
    @Test func handoffFreezesUntilMatchingCommittedOperation() throws {
        var control = TetrisSessionControl(clientID: origin)
        let request = TetrisHandoffRequest(clientID: origin, botID: 7, snapshot: remote().latestSnapshot)
        let token = try control.begin(.create(request))
        #expect(!control.canRunLocal && control.phase == .pending)
        control.markUncertain()
        #expect(control.pending?.requestID == request.requestID && !control.canRunLocal)
        try control.receive(.init(requestID: UUID().uuidString, status: .committed, session: remote()), generation: token)
        #expect(control.phase == .pending)
        try control.receive(.init(requestID: request.requestID, status: .committed, session: remote()), generation: token)
        #expect(control.phase == .botRunning && control.pending == nil)
    }
    @Test func reclaimRequiresCommittedResponseAndWholeSnapshot() throws {
        var control = TetrisSessionControl(clientID: origin)
        try control.receive(remote(), generation: control.generation)
        let request = TetrisCommandRequest(clientID: origin, expectedVersion: 1, expectedEpoch: 1, command: .reclaim)
        let token = try control.begin(.command(sessionID: sid, request: request))
        try control.receive(.init(requestID: request.requestID, status: .pending, session: remote(version: 2)), generation: token)
        #expect(control.phase == .pending && !control.canRunLocal)
        try control.receive(.init(requestID: request.requestID, status: .committed, session: remote(controller: .player, version: 3, epoch: 2)), generation: token)
        #expect(control.phase == .returned && control.canRunLocal)
        #expect(control.remote?.latestSnapshot.phase == .paused)
    }
    @Test func oldGenerationAndOldVersionCannotReplaceNewState() throws {
        var control = TetrisSessionControl(clientID: origin)
        let old = control.generation
        control.reset()
        try control.receive(remote(), generation: old)
        #expect(control.remote == nil)
        try control.receive(remote(version: 4), generation: control.generation)
        try control.receive(remote(version: 2), generation: control.generation)
        #expect(control.remote?.version == 4)
    }
    @Test func otherInstallationCanOnlyWatchReturnedRound() throws {
        var control = TetrisSessionControl(clientID: UUID().uuidString)
        try control.receive(remote(controller: .player), generation: control.generation)
        #expect(!control.canRunLocal && !control.canCommand)
        control.startSeparateLocalRound()
        #expect(control.canRunLocal && control.viewingSeparateLocal)
        #expect(control.remote?.id == sid)
    }
    @Test func malformedOrIncompatibleRemoteCannotUnlockInput() throws {
        var control = TetrisSessionControl(clientID: origin)
        var value = remote()
        value.latestSnapshot.ruleVersion = "unknown"
        #expect(throws: (any Error).self) { try control.receive(value, generation: control.generation) }
        #expect(control.remote == nil)
    }
    @Test func definiteRejectionRestoresPriorLocalControl() throws {
        var control = TetrisSessionControl(clientID: origin)
        let request = TetrisHandoffRequest(clientID: origin, botID: 7, snapshot: remote().latestSnapshot)
        _ = try control.begin(.create(request))
        control.rejectWrite()
        #expect(control.phase == .local && control.pending == nil && control.canRunLocal)
    }
}
