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
    #expect(BotTagRules.maxCount == 3 && BotTagRules.maxLength == 4)
    let cleaned = BotTagRules.normalized(["  研究 ", "", "研究", "写作", "  "])
    #expect(cleaned.error == nil)
    #expect(cleaned.tags == ["研究", "写作"])
    let exact = BotTagRules.normalized(["一二三四"])
    #expect(exact.error == nil && exact.tags == ["一二三四"])
    #expect(BotTagRules.normalized(["一二三四五"]).error == "每个标签最多 4 个字")
    #expect(BotTagRules.normalized((0..<4).map { "标\($0)" }).error == "每个 Bot 最多 3 个标签")
    #expect(BotTagRules.normalized(["研\n究"]).error == "标签不能包含控制字符")
    let blanks = BotTagRules.normalized(["", "   "])
    #expect(blanks.error == nil && blanks.tags.isEmpty)
}

@Test func botTagParseSeparators() {
    // 英文 / 中文逗号、顿号、空格（含全角）都能分隔；多余分隔符与重复被丢掉
    #expect(BotTagRules.parse("搜索, 查询, 调研") == TagNormalization(tags: ["搜索", "查询", "调研"], error: nil))
    #expect(BotTagRules.parse("搜索，查询、调研").tags == ["搜索", "查询", "调研"])
    #expect(BotTagRules.parse(" 搜索  查询\u{3000}调研 ,, ").tags == ["搜索", "查询", "调研"])
    #expect(BotTagRules.parse("搜索, 搜索").tags == ["搜索"])
    #expect(BotTagRules.parse("").tags.isEmpty && BotTagRules.parse("").error == nil)
    #expect(BotTagRules.parse("a, b, c, d").error == "每个 Bot 最多 3 个标签")
    #expect(BotTagRules.parse("搜索引擎优化").error == "每个标签最多 4 个字")
}

@Test func botTagDisplayRoundTrips() {
    #expect(BotTagRules.display(["搜索", "查询", "调研"]) == "搜索, 查询, 调研")
    #expect(BotTagRules.display([]) == "")
    let tags = ["搜索", "查询"]
    #expect(BotTagRules.parse(BotTagRules.display(tags)).tags == tags)
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
