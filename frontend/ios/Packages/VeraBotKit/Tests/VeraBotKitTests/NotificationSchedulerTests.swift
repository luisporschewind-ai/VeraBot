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

@Test func notificationReminderPreferencesAndOverrides() {
    let now = Date(timeIntervalSince1970: 1_759_000_000)
    let rows = [Reminder(id: 1, title: "我", dueUTC: now.addingTimeInterval(600), nextFires: [now.addingTimeInterval(600)]),
                Reminder(id: 2, title: "Bot", dueUTC: now.addingTimeInterval(900), nextFires: [now.addingTimeInterval(900)], createdBy: "bot", sourceBotId: 8)]
    #expect(NotificationPlanner.plan(userID: 1, reminders: rows, now: now, settings: NotificationSettings(enabled: false)).isEmpty)
    #expect(NotificationPlanner.plan(userID: 1, reminders: rows, now: now, settings: NotificationSettings(categories: ["reminder": false])).isEmpty)
    let muted = NotificationPlanner.plan(userID: 1, reminders: rows, now: now, settings: NotificationSettings(mutedBots: [8]))
    #expect(muted.map(\.reminderID) == [1])
    let complete = ReminderLocalOverride(reminderID: 1, action: "complete", until: nil)
    #expect(NotificationPlanner.plan(userID: 1, reminders: rows, now: now, overrides: [complete]).map(\.reminderID) == [2])
    let snooze = ReminderLocalOverride(reminderID: 1, action: "snooze", until: now.addingTimeInterval(1200))
    let planned = NotificationPlanner.plan(userID: 1, reminders: rows, now: now, overrides: [snooze])
    #expect(planned.count == 2)
    #expect(planned.first { $0.reminderID == 1 }?.fireDate == snooze.until)
    #expect(NotificationPlanner.plan(userID: 1, reminders: rows, now: now.addingTimeInterval(1300), overrides: [snooze]).allSatisfy { $0.reminderID != 1 })
}

@Test func notificationRepeatedTimeAndTimezoneAreReconciled() {
    let now = Date(timeIntervalSince1970: 1_759_000_000)
    let a = Reminder(id: 1, title: "每天", dueUTC: now.addingTimeInterval(3600), timeZone: "America/New_York", rrule: "FREQ=DAILY", alertOffsets: [0, -15])
    var b = a; b.dueUTC = a.dueUTC?.addingTimeInterval(3600)
    let old = NotificationPlanner.plan(userID: 1, reminders: [a], now: now)
    let new = NotificationPlanner.plan(userID: 1, reminders: [b], now: now)
    #expect(old.count == 2)
    #expect(old.allSatisfy { $0.timeZone == "America/New_York" })
    let existing = old.map { ScheduledLocalNotification(identifier: $0.identifier, title: $0.title, repeats: $0.repeats, signature: $0.signature) }
    let diff = NotificationPlanner.reconcile(userID: 1, desired: new, existing: existing)
    #expect(diff.add.count == 2)
    #expect(diff.remove.count == 2)
}

@Test func notificationWeekdayAdvanceUsesReminderTimezone() {
    let now = VeraBotDate.parse("2026-10-12T15:00:00Z")!
    let anchor = VeraBotDate.parse("2026-10-12T01:00:00Z")! // Shanghai Monday 09:00
    let reminder = Reminder(id: 1, title: "工作日", dueUTC: anchor, timeZone: "Asia/Shanghai", rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
    let planned = NotificationPlanner.plan(userID: 1, reminders: [reminder], now: now)
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    #expect(planned.count == 5)
    #expect(planned.allSatisfy { $0.fireDate > now && calendar.component(.hour, from: $0.fireDate) == 9 })
}

@Test func notificationChangedSoundReplacesPendingAndDeletedActionDrops() {
    let now = Date()
    let row = Reminder(id: 1, title: "提醒", nextFires: [now.addingTimeInterval(600)])
    let old = NotificationPlanner.plan(userID: 1, reminders: [row], now: now)
    let silent = NotificationPlanner.plan(userID: 1, reminders: [row], now: now, settings: .init(soundEnabled: false))
    let existing = old.map { ScheduledLocalNotification(identifier: $0.identifier, title: $0.title, repeats: $0.repeats, signature: $0.signature) }
    #expect(NotificationPlanner.reconcile(userID: 1, desired: silent, existing: existing).add.count == 1)
    #expect(ReminderOutbox.shouldDrop(status: 404, code: nil))
}

@Test func notificationComplexRuleAndDSTOffsetsUseConcreteOccurrences() {
    let now = VeraBotDate.parse("2027-03-13T12:00:00Z")!
    let anchor = VeraBotDate.parse("2027-03-14T07:15:00Z")! // 03:15 after spring transition
    let reminder = Reminder(id: 4, title: "提前一小时", dueUTC: anchor, timeZone: "America/New_York", rrule: "FREQ=DAILY", nextFires: [anchor], alertOffsets: [0, -60])
    let planned = NotificationPlanner.plan(userID: 1, reminders: [reminder], now: now)
    #expect(planned.contains { !$0.repeats && $0.fireDate == anchor.addingTimeInterval(-3600) })
    let complex = Reminder(id: 5, title: "仅三月", dueUTC: anchor, rrule: "FREQ=DAILY;BYMONTH=3", nextFires: [anchor])
    #expect(NotificationPlanner.plan(userID: 1, reminders: [complex], now: now).allSatisfy { !$0.repeats })
}

@Test func notificationDisplayedRemindersAreCancelledWhenNoLongerEligible() {
    let alerts = ["vb.1.rem.4.100", "vb.1.rem.5.daily", "vb.1.event.thread", "vb.2.rem.4.100"]
    #expect(NotificationPlanner.cancelDelivered(userID: 1, validReminderIDs: [4], identifiers: alerts) == ["vb.1.rem.5.daily"])
    #expect(Set(NotificationPlanner.cancelDelivered(userID: 1, validReminderIDs: [], identifiers: alerts)) == ["vb.1.rem.4.100", "vb.1.rem.5.daily"])
    let rows = [Reminder(id: 4, title: "逾期", status: .due), Reminder(id: 5, title: "已完成", status: .done)]
    #expect(NotificationPlanner.eligibleReminderIDs(rows, settings: .init()) == [4])
    #expect(NotificationPlanner.eligibleReminderIDs(rows, settings: .init(enabled: false)).isEmpty)
}

@Test func notificationOfflineActionFilesAreSeparatedByServer() {
    let a = ReminderOutbox.fileName(userID: 1, server: "https://a.example")
    let b = ReminderOutbox.fileName(userID: 1, server: "https://b.example")
    #expect(a != b)
    #expect(a == ReminderOutbox.fileName(userID: 1, server: "https://a.example"))
}
