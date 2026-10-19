import Foundation
import VeraBotCore
import VeraBotNetworking

struct Bot: Decodable { let id: Int; let name: String }
struct BotsResponse { let bots: [Bot] }
struct TetrisCompanionTurn { let role: String; let content: String; init(role: String, content: String) { self.role = role; self.content = content } }
struct TetrisCompanionReply: Decodable { let text: String }
struct TetrisCompanionRequest {
    let event: String; let score: Int; let lines: Int; let height: Int; let holes: Int
    var cleared = 0; var message = ""; var history: [TetrisCompanionTurn] = []
}
enum BotAvatarState { case idle, smile, success, warning, failure, thinking }
@MainActor final class FakeAPI {
    var pending: [CheckedContinuation<TetrisCompanionReply, Error>] = []
    func bots() async throws -> BotsResponse { fatalError("not used") }
    func tetrisCompanion(botID: Int, request: TetrisCompanionRequest) async throws -> TetrisCompanionReply {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ text: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["text": text])
        pending.removeFirst().resume(returning: try JSONDecoder().decode(TetrisCompanionReply.self, from: data))
    }
}
@MainActor final class AppState {
    let api = FakeAPI()
    var sessionGeneration: UInt64 = 0
    let userID: Int? = 9123456
    func isCurrentSession(_ value: UInt64) -> Bool { value == sessionGeneration }
}
@main struct Check {
    @MainActor static func main() async throws {
        let app = AppState()
        let model = TetrisCompanionModel()
        let bot = try JSONDecoder().decode(Bot.self, from: Data(#"{"id":1,"name":"test","avatar":"bot","color":"333333"}"#.utf8))
        model.selected = bot
        let request = TetrisCompanionRequest(event: "start", score: 0, lines: 0, height: 0, holes: 0)
        func settle() async { try? await Task.sleep(for: .milliseconds(30)) }
        model.send(request, automatic: true, app: app)
        await settle()
        precondition(model.requesting)
        model.prepareConversation()
        precondition(!model.requesting)
        try app.api.finish("stale opening")
        await settle()
        precondition(model.text.isEmpty && model.turns.isEmpty)
        model.newRound()
        model.observe(TetrisCompanionRequest(event: "clear", score: 200, lines: 2, height: 4, holes: 1), ended: false, app: app)
        await settle()
        precondition(model.action == .success && model.requesting)
        try app.api.finish("nice clear")
        await settle()
        precondition(model.action == .success && model.text.isEmpty)
        model.flushPending()
        precondition(model.text == "nice clear")
        model.newRound()
        model.send(request, automatic: true, app: app)
        await settle()
        model.newRound()
        try app.api.finish("stale round")
        await settle()
        precondition(model.text.isEmpty)
        model.send(request, automatic: true, app: app)
        await settle()
        app.sessionGeneration += 1
        try app.api.finish("stale account")
        await settle()
        precondition(model.text.isEmpty)
        model.newRound()
        model.observe(TetrisCompanionRequest(event: "end", score: 200, lines: 0, height: 20, holes: 1), ended: true, app: app)
        await settle()
        precondition(model.action == .failure && model.requesting, "End reaction must stay gentle failure while auto-reply is in flight")
        try app.api.finish("take your time")
        await settle()
        precondition(model.action == .failure)
        model.newRound()
        model.setQuiet(true)
        model.send(request, automatic: true, app: app)
        await settle()
        precondition(app.api.pending.isEmpty)
        var manual = TetrisCompanionRequest(event: "chat", score: 0, lines: 0, height: 0, holes: 0)
        manual.message = "hello"
        model.send(manual, automatic: false, app: app)
        await settle()
        precondition(model.requesting)
        try app.api.finish("manual response")
        await settle()
        precondition(model.text == "manual response")
        model.stop()
        model.newRound()
        model.setQuiet(false)
        model.send(request, automatic: true, app: app)
        await settle()
        try app.api.finish(String(repeating: "陪", count: 60))
        await settle()
        precondition(model.text.count == 24 && model.turns.last?.content.count == 24, "Older server responses must obey the local short bubble limit")
        model.newRound()
        model.observe(TetrisCompanionRequest(event: "clear", score: 800, lines: 8, height: 4, holes: 0), ended: false, app: app)
        await settle()
        precondition(app.api.pending.isEmpty, "Historical multiple clears must not be invented as one clear")
        print("PASS: manual priority, celebration, delayed display, restart/session guards, quiet/manual")
    }
}
