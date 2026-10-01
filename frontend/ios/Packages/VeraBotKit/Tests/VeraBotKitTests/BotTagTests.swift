import Foundation
import Testing
@testable import VeraBotCore

@Test func botTagsDefaultWhenMissing() throws {
    let json = ##"{"id":7,"name":"Vera","avatar":"🐼","color":"#0F766E"}"##
    let bot = try JSONDecoder().decode(Bot.self, from: Data(json.utf8))
    #expect(bot.tags.isEmpty)
}

@Test func botTagsDecode() throws {
    let json = ##"{"id":7,"name":"Vera","avatar":"🐼","color":"#0F766E","tags":["研究","写作"]}"##
    let bot = try JSONDecoder().decode(Bot.self, from: Data(json.utf8))
    #expect(bot.tags == ["研究", "写作"])
}

@Test func botTagsNullBecomesEmpty() throws {
    let json = ##"{"id":7,"name":"Vera","avatar":"🐼","color":"#0F766E","tags":null}"##
    let bot = try JSONDecoder().decode(Bot.self, from: Data(json.utf8))
    #expect(bot.tags.isEmpty)
}

@Test func botTagRulesMatchServer() {
    let cleaned = BotTagRules.normalized(["  研究 ", "", "研究", "写作", "  "])
    #expect(cleaned.error == nil)
    #expect(cleaned.tags == ["研究", "写作"])
    let exact = BotTagRules.normalized(["一二三四五六七八九十甲乙"])
    #expect(exact.error == nil && exact.tags == ["一二三四五六七八九十甲乙"])
    #expect(BotTagRules.normalized(["一二三四五六七八九十甲乙丙"]).error == "每个标签最多 12 个字")
    #expect(BotTagRules.normalized((0..<6).map { "标\($0)" }).error == "每个 Bot 最多 5 个标签")
    #expect(BotTagRules.normalized(["研\n究"]).error == "标签不能包含控制字符")
    let blanks = BotTagRules.normalized(["", "   "])
    #expect(blanks.error == nil && blanks.tags.isEmpty)
}

@Test func botCreateEncodesTags() throws {
    let data = try JSONEncoder().encode(BotCreate(name: "Vera", avatar: "🤖", color: "#000", persona: "", instructions: "", tags: ["研究"]))
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj?["tags"] as? [String] == ["研究"])
}

@Test func botPatchOmitsNilTags() throws {
    let onlyName = try JSONEncoder().encode(BotPatch(name: "Vera"))
    let nameObj = try JSONSerialization.jsonObject(with: onlyName) as? [String: Any]
    #expect(nameObj?.keys.sorted() == ["name"])
    let withTags = try JSONEncoder().encode(BotPatch(tags: []))
    let tagsObj = try JSONSerialization.jsonObject(with: withTags) as? [String: Any]
    #expect(tagsObj?.keys.sorted() == ["tags"])
    #expect((tagsObj?["tags"] as? [String])?.isEmpty == true)
}
