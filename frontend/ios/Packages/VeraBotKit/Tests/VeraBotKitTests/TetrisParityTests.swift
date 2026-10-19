import Foundation
import Testing
@testable import VeraBotCore

@Suite struct TetrisParityTests {
    private struct Step: Decodable { let action: TetrisAction?; let elapsed: Int? }
    private struct Fixture: Decodable {
        let name: String
        let initial: TetrisState
        let steps: [Step]
        let expectedSnapshot: TetrisState
        let expectedEvents: [TetrisEvent]
    }
    private struct Fixtures: Decodable { let ruleVersion: String; let cases: [Fixture]; let seed42Initial: TetrisState; let seed42BagSequence: [TetrisKind] }
    private func load() throws -> Fixtures {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: root.appendingPathComponent("docs/contracts/tetris-v2-fixtures.json")))
    }
    @Test func seededInitializationAndTwentyOneBagPiecesAgree() throws {
        let fixtures = try load()
        var game = TetrisGame(seed: 42, ruleVersion: "vera-tetris-2")
        #expect(game.state == fixtures.seed42Initial)
        game.apply(.start)
        var pieces: [TetrisKind] = []
        for _ in 0..<21 {
            pieces.append(game.activeKind)
            game.apply(.hardDrop)
            var state = game.state
            state.board = Array(repeating: 0, count: 200)
            game = try TetrisGame(restoring: state)
        }
        #expect(pieces == fixtures.seed42BagSequence)
    }
    @Test func sharedHandCalculatedContractFixtures() throws {
        let fixtures = try load()
        #expect(fixtures.ruleVersion == "vera-tetris-2")
        for fixture in fixtures.cases {
            var game = try TetrisGame(restoring: fixture.initial)
            var events: [TetrisEvent] = []
            for step in fixture.steps {
                if let action = step.action { events += game.apply(action) }
                else if let elapsed = step.elapsed { events += game.advance(milliseconds: elapsed) }
            }
            #expect(game.state == fixture.expectedSnapshot, Comment(rawValue: fixture.name))
            #expect(events == fixture.expectedEvents, Comment(rawValue: fixture.name))
        }
    }
}
