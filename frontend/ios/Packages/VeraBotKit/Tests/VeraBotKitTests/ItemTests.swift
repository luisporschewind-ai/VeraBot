import Foundation
import Testing
@testable import VeraBotCore

@Suite struct ItemTests {
    @Test func itemDecodesChecklistAndTaskSummary() throws {
        let json = """
        {"id":7,"title":"整理","content":"整理","status":"scheduled","timezone":"Asia/Shanghai",
         "all_day":false,"priority":0,"created_by":"user","notify":false,"alert_offsets":[0],"version":2,"done":0,
         "checklist_done":1,"checklist_total":2,"task_kind":"owned","task_id":20,"source_kind":"manual",
         "checklist":[{"id":1,"text":"A","done":true,"position":0},{"id":2,"text":"B","done":false,"position":1}],
         "task":{"kind":"owned","id":20,"status":"等你处理","status_key":"needs_user","needs_user":true,
                 "last_result_summary":"请确认下一步","bot_id":3}}
        """
        let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        #expect(item.id == 7)
        #expect(item.checklistTotal == 2)
        #expect(item.checklistDone == 1)
        #expect(item.checklistProgressText == "1/2")
        #expect(item.checklist.count == 2)
        #expect(item.task?.status == "等你处理")
        #expect(item.task?.needsUser == true)
        #expect(item.hasTask)
    }

    @Test func itemGroupingFiveGroupsAndBotFilter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 10))!

        func item(id: Int, title: String, status: ReminderStatus = .scheduled, due: Date? = nil,
                  taskId: Int? = nil, checklistDone: Int = 0, checklistTotal: Int = 0) -> Item {
            Item(reminder: Reminder(
                id: id, title: title, dueUTC: due, status: status, taskId: taskId,
                checklistDone: checklistDone, checklistTotal: checklistTotal
            ), task: taskId.map { ItemTaskSummary(kind: "owned", id: $0, status: "待执行") })
        }

        let overdue = item(id: 1, title: "逾期", due: now.addingTimeInterval(-3600))
        let today = item(id: 2, title: "今天", due: now.addingTimeInterval(3600))
        let planned = item(id: 3, title: "计划", due: now.addingTimeInterval(86400 * 2))
        let todo = item(id: 4, title: "待办", checklistDone: 2, checklistTotal: 5)
        let bot = item(id: 5, title: "Bot", due: now.addingTimeInterval(7200), taskId: 9)
        let done = item(id: 6, title: "完成", status: .done, due: now)

        let sections = ItemGrouping.sections(
            [overdue, today, planned, todo, bot, done], filter: .all, showDone: true, now: now, calendar: calendar)
        #expect(sections.map(\.0) == [.today, .planned, .todo, .bot, .done])
        #expect(sections[0].1.map(\.id) == [1, 2])
        #expect(sections.first { $0.0 == .todo }?.1.first?.checklistProgressText == "2/5")
        #expect(ItemGrouping.sections([bot, todo], filter: .botTasksOnly, showDone: false, now: now, calendar: calendar)
            .flatMap(\.1).map(\.id) == [5])
    }

    @Test func reminderStillDecodesWithoutV37Fields() throws {
        let json = #"{"id":1,"content":"旧","done":0}"#
        let reminder = try JSONDecoder().decode(Reminder.self, from: Data(json.utf8))
        #expect(reminder.checklistTotal == 0)
        #expect(reminder.taskId == nil)
    }
}
