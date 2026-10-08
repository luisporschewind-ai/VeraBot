import Testing
@testable import VeraBotCore

@Test func appearanceRequestsRejectSwitchAccountServerAndLateCompletion() {
    var gate = BotAppearanceRequestGate()
    let first = gate.begin(botID: 7, generation: 1, server: "A")
    #expect(gate.accepts(first, botID: 7, generation: 1, server: "A"))
    #expect(!gate.accepts(first, botID: 8, generation: 1, server: "A"))
    #expect(!gate.accepts(first, botID: 7, generation: 2, server: "A"))
    #expect(!gate.accepts(first, botID: 7, generation: 1, server: "B"))
    let newer = gate.begin(botID: 8, generation: 1, server: "A")
    #expect(!gate.accepts(first, botID: 7, generation: 1, server: "A"))
    #expect(gate.accepts(newer, botID: 8, generation: 1, server: "A"))
    gate.invalidate()
    #expect(!gate.accepts(newer, botID: 8, generation: 1, server: "A"))
}
