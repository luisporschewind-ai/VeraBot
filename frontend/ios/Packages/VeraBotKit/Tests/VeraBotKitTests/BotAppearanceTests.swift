import Foundation
import Testing
@testable import VeraBotCore

private let appearanceFixture = #"{"schema_version":1,"template_id":"cx-robot","template_version":1,"palette":{"body":{"space":"display-p3","red":0.917647,"green":0.25098,"blue":0.270588},"eyes":{"space":"srgb","red":0.972549,"green":0.972549,"blue":0.964706}},"parameters":{"roundness":0.5}}"#
private func appearanceJSON(_ string: String = appearanceFixture) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(string.utf8))
}
private func appearanceBot(_ extra: String = "") throws -> Bot {
    try JSONDecoder().decode(Bot.self, from: Data((##"{"id":7,"name":"Vera","avatar":"veraBean","color":"#0F766E""## + extra + "}").utf8))
}
@Test func appearanceP3RoundTrip() throws {
    let a = try JSONDecoder().decode(BotAppearance.self, from: Data(appearanceFixture.utf8))
    #expect(a.palette.body.space == .displayP3)
    #expect(a.palette.body.red == 0.917647)
    #expect(a.palette.eyes.space == .sRGB)
    #expect(try a.jsonValue() == appearanceJSON())
}
@Test func legacyBotWithoutAppearanceDecodes() throws {
    let bot = try appearanceBot()
    #expect(bot.appearance == nil && !bot.appearanceFieldPresent)
    #expect(bot.supportedAppearance == nil && bot.avatar == "veraBean")
    let clear = try appearanceBot(",\"appearance\":null")
    #expect(clear.appearanceFieldPresent && clear.appearance == nil)
}
@Test func unknownVersionAndTemplateSurviveBotDecode() throws {
    for raw in [appearanceFixture.replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":9"),
                appearanceFixture.replacingOccurrences(of: "cx-robot", with: "future-bot")] {
        let bot = try appearanceBot(",\"appearance\":" + raw)
        #expect(bot.appearance == (try appearanceJSON(raw)))
        #expect(bot.appearanceFieldPresent)
        let encoded = try JSONEncoder().encode(bot)
        let restored = try JSONDecoder().decode(Bot.self, from: encoded)
        #expect(restored.appearance == bot.appearance)
    }
    let future = try appearanceBot(",\"appearance\":" + appearanceFixture.replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":9"))
    #expect(future.supportedAppearance == nil)
}
@Test func patchAppearanceOmittedNullAndObject() throws {
    let absent = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(BotPatch(name:"V")))
    #expect(absent["appearance"] == nil)
    let clear = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(BotPatch(appearance:.null)))
    #expect(clear["appearance"] == .null)
    let raw = try appearanceJSON()
    let replacement = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(BotPatch(appearance:raw)))
    #expect(replacement["appearance"] == raw)
    #expect(replacement["avatar"] == nil && replacement["color"] == nil)
}
@Test func appearanceRejectsInvalidValues() throws {
    let mutations = [
        ("\"red\":0.917647", "\"red\":-0.1"), ("\"red\":0.917647", "\"red\":1.1"),
        ("\"red\":0.917647", "\"red\":true"), ("\"roundness\":0.5", "\"roundness\":2"),
        ("\"schema_version\":1", "\"schema_version\":true"), ("\"schema_version\":1", "\"schema_version\":2"),
        ("\"template_version\":1", "\"template_version\":0"), ("cx-robot", "Bad ID"),
        ("display-p3", "unknown"), ("\"roundness\":0.5", "\"roundness\":0.5,\"script\":\"x\"")
    ]
    for (from,to) in mutations {
        let data = Data(appearanceFixture.replacingOccurrences(of:from,with:to).utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(BotAppearance.self,from:data) }
    }
    var a = BotAppearance.robotDefault
    a.palette.body.red = .nan
    #expect(throws: (any Error).self) { try a.validate() }
    let huge = appearanceFixture.replacingOccurrences(of:"cx-robot",with:String(repeating:"a",count:5000))
    #expect(throws: (any Error).self) { try JSONDecoder().decode(BotAppearance.self,from:Data(huge.utf8)) }
}
