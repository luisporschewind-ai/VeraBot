import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotTTS

@Test func decodesBotWithDefaults() throws {
    let json = ##"{"id":7,"name":"Vera","avatar":"🐼","color":"#0F766E"}"##
    let bot = try JSONDecoder().decode(Bot.self, from: Data(json.utf8))
    #expect(bot.name == "Vera")
    #expect(bot.allowedTools.isEmpty)
    #expect(bot.acceptDelegation == false)
}

@Test func botPatchOmitsNilFields() throws {
    let data = try JSONEncoder().encode(BotPatch(name: "Vera"))
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj?.keys.sorted() == ["name"])
}

@Test func jsonValueText() throws {
    let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":1,"b":[true,"x"]}"#.utf8))
    #expect(v["a"]?.text == "1")
    #expect(v["b"]?.text == "true, x")
}

@MainActor @Test func ttsPlainTextStripsMarkdown() {
    #expect(SpeechPlayer.plainText("**结论**：`ok`") == "结论：ok")
}
