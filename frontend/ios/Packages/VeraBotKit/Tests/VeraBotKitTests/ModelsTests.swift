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
    #expect(bot.pinnedAt == nil)
    #expect(!bot.isPinned)
}

@Test func botPinDecodingPatchAndOrdering() throws {
    let decoder = JSONDecoder()
    let a = try decoder.decode(Bot.self, from: Data(##"{"id":1,"name":"A","avatar":"🤖","color":"#000","pinned_at":"2026-10-01T10:00:00+00:00"}"##.utf8))
    let b = try decoder.decode(Bot.self, from: Data(##"{"id":2,"name":"B","avatar":"🤖","color":"#000","pinned_at":"2026-10-01T11:00:00+00:00"}"##.utf8))
    let c = try decoder.decode(Bot.self, from: Data(##"{"id":3,"name":"C","avatar":"🤖","color":"#000","pinned_at":null}"##.utf8))
    let tied = try decoder.decode(Bot.self, from: Data(##"{"id":0,"name":"Tied","avatar":"🤖","color":"#000","pinned_at":"2026-10-01T10:00:00+00:00"}"##.utf8))
    #expect(a.pinnedAt != nil && a.isPinned)
    #expect(!c.isPinned)
    #expect(BotOrdering.sorted([c, a, b]).map(\.id) == [2, 1, 3])
    #expect(BotOrdering.sorted([a, tied]).map(\.id) == [0, 1])
    let data = try JSONEncoder().encode(BotPatch(pinned: true))
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj?[
        "pinned"] as? Bool == true)
    let empty = try JSONEncoder().encode(BotPatch(name: "A"))
    let emptyObj = try JSONSerialization.jsonObject(with: empty) as? [String: Any]
    #expect(emptyObj?.keys.sorted() == ["name"])
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

// MARK: - 会话列表时间（ListTimestamp）

private func shanghaiCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    cal.firstWeekday = 2   // 周一为一周第一天
    cal.locale = Locale(identifier: "zh_Hans_CN")
    return cal
}

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    shanghaiCalendar().date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Test func listTimestampParsesBackendISO() {
    #expect(ListTimestamp.parse("2026-10-01T02:28:50+00:00") != nil)
    #expect(ListTimestamp.parse("2026-10-01T02:28:50.123Z") != nil)
    #expect(ListTimestamp.parse("") == nil)
    #expect(ListTimestamp.parse(nil) == nil)
}

@Test func listTimestampFormats() {
    let cal = shanghaiCalendar()
    let now = at(2026, 10, 1, 11, 58)   // 周四
    #expect(ListTimestamp.label(for: at(2026, 10, 1, 9, 5), now: now, calendar: cal) == "09:05")
    #expect(ListTimestamp.label(for: at(2026, 9, 30, 23, 0), now: now, calendar: cal) == "昨天")
    #expect(ListTimestamp.label(for: at(2026, 9, 28), now: now, calendar: cal) == "星期一")
    #expect(ListTimestamp.label(for: at(2026, 9, 27), now: now, calendar: cal) == "9/27")
    #expect(ListTimestamp.label(for: at(2025, 12, 31), now: now, calendar: cal) == "2025/12/31")
}

@Test func listTimestampFallsBackToCreatedAt() throws {
    let withMsg = ##"{"id":1,"name":"a","avatar":"🤖","color":"#000","created_at":"2026-09-01T00:00:00+00:00","last_message":{"content":"hi","created_at":"2026-10-01T02:28:50+00:00"}}"##
    let noMsg = ##"{"id":2,"name":"b","avatar":"🤖","color":"#000","created_at":"2026-09-01T00:00:00+00:00","last_message":null}"##
    let a = try JSONDecoder().decode(Bot.self, from: Data(withMsg.utf8))
    let b = try JSONDecoder().decode(Bot.self, from: Data(noMsg.utf8))
    #expect(ListTimestamp.rowDate(for: a) == ListTimestamp.parse("2026-10-01T02:28:50+00:00"))
    #expect(ListTimestamp.rowDate(for: b) == ListTimestamp.parse("2026-09-01T00:00:00+00:00"))
}

@Test func botOptimisticPinToggle() throws {
    let decoder = JSONDecoder()
    func bot(_ id: Int, _ pinned: String?) throws -> Bot {
        let p = pinned.map { "\"\($0)\"" } ?? "null"
        return try decoder.decode(Bot.self, from: Data(##"{"id":\##(id),"name":"B\##(id)","avatar":"🤖","color":"#000","pinned_at":\##(p)}"##.utf8))
    }
    let now = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21T14:13:20Z
    #expect(BotOrdering.pinTimestamp(now) == "2026-09-21T14:13:20+00:00")
    let list = BotOrdering.sorted([try bot(1, "2026-09-01T10:00:00+00:00"), try bot(2, nil), try bot(3, nil)])
    // 置顶 3：本地立即排到最前，格式与后端一致
    let pinned = BotOrdering.togglingPin(list, id: 3, now: now)
    #expect(pinned.map(\.id) == [3, 1, 2])
    #expect(pinned.first?.pinnedAt == "2026-09-21T14:13:20+00:00")
    // 本机时钟比已有置顶时间更早时，仍排在最前
    let skewed = BotOrdering.togglingPin(list, id: 2, now: Date(timeIntervalSince1970: 0))
    #expect(skewed.first?.id == 2)
    // 取消置顶：回到按 id 的位置
    #expect(BotOrdering.togglingPin(pinned, id: 3, now: now).map(\.id) == [1, 2, 3])
    // 服务端校正：只改值、顺序不变
    let reconciled = BotOrdering.replacingPinnedAt(pinned, id: 3, value: "2026-09-21T14:13:21+00:00")
    #expect(reconciled.map(\.id) == [3, 1, 2])
    // 未知 id 不变
    #expect(BotOrdering.togglingPin(list, id: 99).map(\.id) == list.map(\.id))
}
