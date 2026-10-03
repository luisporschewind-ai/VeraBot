import Foundation
import Testing
@testable import VeraBotCore

@Test func reminderDecodesOldAndNewJSON() throws {
    let legacy = ##"{"id":3,"content":"带伞","due_at":"2026-10-04T09:00:00+08:00","done":0,"bot_name":"Vera"}"##
    let old = try JSONDecoder().decode(Reminder.self, from: Data(legacy.utf8))
    #expect(old.title == "带伞")
    #expect(old.content == "带伞")
    #expect(old.status == .scheduled)
    #expect(old.done == 0)
    #expect(old.botName == "Vera")
    #expect(old.version == 1)
    #expect(old.dueUTC == nil)

    let modern = """
    {"id":8,"title":"交周报","content":"交周报","note":null,"due_at":"2026-10-04T09:00:00+08:00",
     "due_utc":"2026-10-04T01:00:00+00:00","timezone":"Asia/Shanghai","all_day":false,
     "rrule":"FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR","repeat_label":"工作日 09:00",
     "next_fires":["2026-10-05T01:00:00+00:00"],"status":"scheduled","snoozed_until":null,
     "priority":2,"created_by":"bot","bot_id":4,"source_bot_id":4,"bot_name":"研究助手",
     "assignee_bot_id":4,"assignee_bot_name":"研究助手","source_message_id":9,"notify":true,
     "alert_offsets":[0],"version":3,"done":0,"completed_at":null,"cancelled_at":null,
     "created_at":"2026-10-03T02:00:00+00:00","updated_at":"2026-10-03T02:00:00+00:00"}
    """
    let item = try JSONDecoder().decode(Reminder.self, from: Data(modern.utf8))
    #expect(item.sourceBotId == 4)
    #expect(item.nextFires.count == 1)
    #expect(item.dueUTC != nil)
    #expect(item.status == .scheduled)
    let unknown = try JSONDecoder().decode(Reminder.self, from: Data(#"{"id":1,"title":"x","status":"firing"}"#.utf8))
    #expect(unknown.status == .unknown)
}

@Test func reminderGroupingAndDeviceTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let now = date("2026-10-03T02:00:00+00:00")
    let due = Reminder(id: 1, title: "逾期", dueUTC: date("2026-10-03T01:00:00+00:00"), status: .due)
    let today = Reminder(id: 2, title: "今天", dueUTC: date("2026-10-03T07:00:00+00:00"), status: .scheduled, repeatLabel: "工作日 09:00", botName: "研究助手")
    let later = Reminder(id: 3, title: "以后", dueUTC: date("2026-10-05T01:00:00+00:00"), status: .scheduled)
    let undated = Reminder(id: 4, title: "没时间", status: .scheduled, notify: false)
    let missed = Reminder(id: 5, title: "错过", dueUTC: date("2026-10-02T01:00:00+00:00"), status: .missed, updatedAt: "2026-10-02T01:00:00+00:00")
    let done = Reminder(id: 6, title: "完成", status: .done, completedAt: "2026-10-03T01:00:00+00:00")
    let oldDone = Reminder(id: 7, title: "很久", status: .done, completedAt: "2020-01-01T00:00:00+00:00")
    let sections = ReminderGrouping.sections([later, undated, missed, done, oldDone, due, today], filter: .all, showDone: true, now: now, calendar: calendar)
    #expect(sections.map(\.0) == [.due, .today, .upcoming, .undated, .missed, .done])
    #expect(sections[0].1.map(\.id) == [1])
    #expect(!sections.contains { $0.1.contains { $0.id == 7 } })
    let text = ReminderTimeText.subtitle(today, now: now, calendar: calendar)
    #expect(text.contains("今天"))
    #expect(text.contains("15:00") || text.contains("07:00") == false)
    #expect(text.contains("研究助手"))
    #expect(!text.contains("2026-10-03T"))
    let hidden = ReminderGrouping.sections([done], filter: .all, showDone: false, now: now, calendar: calendar)
    #expect(hidden.isEmpty)
    let mine = Reminder(id: 8, title: "我的", createdBy: "user")
    let bot = Reminder(id: 9, title: "Bot", createdBy: "bot", sourceBotId: 2)
    #expect(ReminderGrouping.matches(mine, filter: .createdByUser))
    #expect(!ReminderGrouping.matches(bot, filter: .createdByUser))
    #expect(ReminderGrouping.matches(bot, filter: .bot(2)))
}

@Test func deletedBotNameAndRepeatPreset() {
    let gone = Reminder(id: 1, title: "还在", createdBy: "bot", sourceBotId: nil, botName: nil)
    #expect(gone.sourceName == "已删除的 Bot")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    let monday = date("2026-10-05T01:00:00+00:00")
    #expect(ReminderRepeatPreset.weekly.rrule(on: monday, calendar: calendar) == "FREQ=WEEKLY;BYDAY=MO")
    #expect(ReminderRepeatPreset.matching("FREQ=DAILY") == .daily)
    #expect(ReminderRepeatPreset.never.rrule(on: nil) == nil)
}

private func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}
