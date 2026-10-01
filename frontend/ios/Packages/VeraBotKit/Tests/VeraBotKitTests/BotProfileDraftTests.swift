import Foundation
import Testing
@testable import VeraBotCore

private func bot(hasAvatar: Bool = false, tags: [String] = ["研究"]) throws -> Bot {
    let tagJSON = tags.map { "\"\($0)\"" }.joined(separator: ",")
    let json = ##"{"id":3,"name":"小研","avatar":"🦉","color":"#0F766E","has_avatar":\##(hasAvatar),"tags":[\##(tagJSON)]}"##
    return try JSONDecoder().decode(Bot.self, from: Data(json.utf8))
}

@Test func draftStartsClean() throws {
    let d = BotProfileDraft(bot: try bot())
    #expect(d.name == "小研" && d.tags == ["研究"] && d.photo == .unchanged)
    #expect(!d.isDirty && !d.showsPhoto && !d.canUseDefaultLook)
    #expect(d.tagsText == "研究")
}

@Test func draftRenameTrimsAndRejectsEmpty() throws {
    var d = BotProfileDraft(bot: try bot())
    #expect(d.rename("   ") == "昵称不能为空")
    #expect(d.name == "小研" && !d.isDirty)            // 出错保留原值
    #expect(d.rename(String(repeating: "研", count: 21)) == "昵称最多 20 个字")
    #expect(d.name == "小研")
    #expect(d.rename("  大研 ") == nil)
    #expect(d.name == "大研" && d.isDirty)
    #expect(d.rename("小研") == nil)
    #expect(!d.isDirty)                                 // 改回原值不算改动
}

@Test func draftTagsUseSameRules() throws {
    var d = BotProfileDraft(bot: try bot())
    #expect(d.setTags("搜索, 查询、调研 写作") == "每个 Bot 最多 3 个标签")
    #expect(d.tags == ["研究"])
    #expect(d.setTags("超过四个字") == "每个标签最多 4 个字")
    #expect(d.tags == ["研究"])
    #expect(d.setTags("搜索，查询 搜索") == nil)
    #expect(d.tags == ["搜索", "查询"] && d.tagsText == "搜索, 查询" && d.isDirty)
    #expect(d.setTags("  ") == nil)
    #expect(d.tags.isEmpty)                             // 空 = 清空（PATCH 发 []）
}

@Test func draftPhotoPendingStates() throws {
    var d = BotProfileDraft(bot: try bot())
    d.choosePhoto(Data([1, 2, 3]))
    #expect(d.photo == .replace(Data([1, 2, 3])) && d.showsPhoto && d.canUseDefaultLook && d.isDirty)
    d.useDefaultLook()                                  // 未保存的新照片 → 直接撤销
    #expect(d.photo == .unchanged && !d.showsPhoto && !d.isDirty)

    var s = BotProfileDraft(bot: try bot(hasAvatar: true))
    #expect(s.showsPhoto && s.canUseDefaultLook)
    s.useDefaultLook()                                  // 已保存的照片 → 保存时删除
    #expect(s.photo == .remove && !s.showsPhoto && !s.canUseDefaultLook && s.isDirty)
    s.choosePhoto(Data([9]))
    #expect(s.photo == .replace(Data([9])) && s.showsPhoto)
    s.useDefaultLook()
    #expect(s.photo == .remove)
}

@Test func botLookColorMatchIgnoresCase() {
    #expect(BotLook.sameColor("#0F766E", "#0f766e"))
    #expect(!BotLook.sameColor("#0F766E", "#14b8a6"))
    #expect(BotLook.colors.count == 8 && BotLook.emojis.count == 16)
}

@Test func toolDisplayNameHidesRawName() throws {
    func tool(_ label: String?) throws -> ToolInfo {
        let l = label.map { "\"\($0)\"" } ?? "null"
        return try JSONDecoder().decode(ToolInfo.self, from: Data(#"{"name":"get_weather","label":\#(l),"description":"d"}"#.utf8))
    }
    #expect(try tool("天气查询").displayName == "天气查询")
    #expect(try tool(nil).displayName == "未命名工具")
    #expect(try tool(" ").displayName == "未命名工具")
    #expect(try tool("get_weather").displayName == "未命名工具")   // 后端对未知工具回退为原始名
}

@Test func delegationTimeIsLocal() throws {
    let date = try #require(ListTimestamp.parse("2026-10-01T09:32:00+00:00"))
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    #expect(ListTimestamp.fullLabel(for: date, calendar: cal) == "2026/10/1 17:32")
}
