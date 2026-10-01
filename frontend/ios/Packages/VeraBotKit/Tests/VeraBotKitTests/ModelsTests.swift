import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotTTS

@Test func userFallsBackToUsername() throws {
    let json = ##"{"id":1,"username":"demo"}"##
    let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
    #expect(user.displayName == "demo")
    #expect(user.nickname == nil)
    #expect(user.hasAvatar == false)
}

@Test func userUsesServerDisplayName() throws {
    let json = ##"{"id":1,"username":"demo","nickname":"小云","display_name":"小云","has_avatar":true,"avatar_updated_at":"t"}"##
    let user = try JSONDecoder().decode(User.self, from: Data(json.utf8))
    #expect(user.displayName == "小云")
    #expect(user.hasAvatar)
    #expect(user.avatarUpdatedAt == "t")
}

@Test func nicknameRulesMatchServer() {
    #expect(NicknameRules.cleaned("  小云  ") == "小云")
    #expect(NicknameRules.cleaned("   ") == nil)
    #expect(NicknameRules.cleaned("") == nil)
    #expect(NicknameRules.cleaned(String(repeating: "名", count: 32))?.count == 32)
    #expect(NicknameRules.cleaned(String(repeating: "名", count: 33)) == nil)
    #expect(NicknameRules.cleaned("a\nb") == nil)
}

@Test func decodesBotWithDefaults() throws {
    let json = ##"{"id":7,"name":"Vera","avatar":"🐼","color":"#0F766E"}"##
    let bot = try JSONDecoder().decode(Bot.self, from: Data(json.utf8))
    #expect(bot.name == "Vera")
    #expect(bot.allowedTools.isEmpty)
    #expect(bot.acceptDelegation == false)
    #expect(bot.hasAvatar == false)
    #expect(bot.avatarUpdatedAt == nil)
}

@Test func decodesBotAvatarFlags() throws {
    let json = ##"{"id":7,"name":"Vera","avatar":"🐼","color":"#0F766E","has_avatar":true,"avatar_updated_at":"t"}"##
    let bot = try JSONDecoder().decode(Bot.self, from: Data(json.utf8))
    #expect(bot.hasAvatar)
    #expect(bot.avatarUpdatedAt == "t")
    #expect(bot.avatar == "🐼")
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
