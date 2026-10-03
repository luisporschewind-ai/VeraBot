import Foundation
import Testing
@testable import VeraBotCore

@Test func plannerCapsAtSixtyInsideHorizon() {
    let now = Date(timeIntervalSince1970: 1_759_000_000)
    var reminders: [Reminder] = []
    for index in 0..<70 {
        let fire = now.addingTimeInterval(TimeInterval((index + 1) * 3600))
        reminders.append(Reminder(id: index + 1, title: "第\(index)", dueUTC: fire, nextFires: [fire], status: .scheduled))
    }
    let far = now.addingTimeInterval(20 * 24 * 3600)
    reminders.append(Reminder(id: 99, title: "太远", dueUTC: far, nextFires: [far], status: .scheduled))
    let planned = NotificationPlanner.plan(userID: 7, reminders: reminders, now: now)
    #expect(planned.count == 60)
    #expect(planned.allSatisfy { $0.fireDate <= now.addingTimeInterval(NotificationPlanner.horizon) })
    #expect(planned.first?.reminderID == 1)
    #expect(!planned.contains { $0.reminderID == 99 })
    #expect(planned.allSatisfy { !$0.repeats })
}

@Test func simpleRepeatsUseCalendarTriggers() {
    let now = Date(timeIntervalSince1970: 1_759_000_000)
    let daily = Reminder(id: 1, title: "每天", dueUTC: now.addingTimeInterval(3600), rrule: "FREQ=DAILY",
                         nextFires: [now.addingTimeInterval(3600)], status: .scheduled)
    let weekdays = Reminder(id: 2, title: "上班", dueUTC: now.addingTimeInterval(7200),
                            rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", nextFires: [now.addingTimeInterval(7200)], status: .scheduled)
    let counted = Reminder(id: 3, title: "三次", dueUTC: now.addingTimeInterval(1800), rrule: "FREQ=DAILY;COUNT=3",
                           nextFires: [now.addingTimeInterval(1800), now.addingTimeInterval(90000)], status: .scheduled)
    let planned = NotificationPlanner.plan(userID: 4, reminders: [daily, weekdays, counted], now: now, preview: "title")
    let dailyItem = planned.first { $0.reminderID == 1 }
    #expect(dailyItem?.repeats == true)
    #expect(dailyItem?.identifier == "vb.4.rem.1.daily")
    let days = planned.filter { $0.reminderID == 2 }
    #expect(days.count == 5)
    #expect(days.allSatisfy { $0.repeats })
    #expect(Set(days.map(\.identifier)) == Set((1...5).map { "vb.4.rem.2.wd.\($0)" }))
    let limited = planned.filter { $0.reminderID == 3 }
    #expect(limited.allSatisfy { !$0.repeats })
    #expect(limited.count == 2)
    let hidden = NotificationPlanner.plan(userID: 4, reminders: [daily], now: now, preview: "none")
    #expect(hidden.first?.title == "你有一条新通知")
}

@Test func reconcileAddsRemovesAndReplaces() {
    let now = Date(timeIntervalSince1970: 1_759_000_000)
    let desired = [
        PlannedNotification(identifier: "vb.1.rem.2.daily", reminderID: 2, userID: 1, title: "新标题", fireDate: now, repeats: true),
        PlannedNotification(identifier: "vb.1.rem.3.100", reminderID: 3, userID: 1, title: "一次", fireDate: now, repeats: false),
    ]
    let existing = [
        ScheduledLocalNotification(identifier: "vb.1.rem.2.daily", title: "旧标题", repeats: true),
        ScheduledLocalNotification(identifier: "vb.1.rem.9.1", title: "多余", repeats: false),
        ScheduledLocalNotification(identifier: "other.app", title: "别的", repeats: false),
    ]
    let diff = NotificationPlanner.reconcile(userID: 1, desired: desired, existing: existing)
    #expect(Set(diff.remove) == Set(["vb.1.rem.2.daily", "vb.1.rem.9.1"]))
    #expect(Set(diff.add.map(\.identifier)) == Set(["vb.1.rem.2.daily", "vb.1.rem.3.100"]))
}

@Test func outboxKeepsIdempotencyAndDropsConflicts() {
    let first = ReminderOutboxItem(idempotencyKey: "vb.1.rem.5.done", reminderID: 5, action: "complete")
    let again = ReminderOutbox.appending(first, to: ReminderOutbox.appending(first, to: []))
    #expect(again.count == 1)
    #expect(ReminderOutbox.fileName(userID: 5) == "outbox-5.json")
    let data = ReminderOutbox.encode(again)
    #expect(ReminderOutbox.decode(data) == again)
    #expect(ReminderOutbox.shouldDrop(status: 409, code: "invalid_transition"))
    #expect(ReminderOutbox.shouldDrop(status: 409, code: "version_conflict"))
    #expect(!ReminderOutbox.shouldDrop(status: 500, code: nil))
    let defaults = UserDefaults(suiteName: "vb.device.test")!
    defaults.removePersistentDomain(forName: "vb.device.test")
    let created = DeviceIdentity.current(defaults: defaults)
    #expect(DeviceIdentity.current(defaults: defaults) == created)
    let rotated = DeviceIdentity.rotate(defaults: defaults)
    #expect(rotated != created)
}
