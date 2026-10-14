import Foundation
import Testing
@testable import VeraBotCore

private func eventNote(id: Int = 1, created: Date, read: Bool = false, category: String = "bot_message") throws -> InboxNotification {
    let json: [String: Any] = ["id": id, "category": category, "title": "研究助手有新消息", "logical_key": "reply:\(id)",
        "message_id": id, "bot_id": 8, "thread_id": "bot:8", "created_at": VeraBotDate.format(created),
        "read_at": read ? VeraBotDate.format(created) as Any : NSNull()]
    return try JSONDecoder().decode(InboxNotification.self, from: JSONSerialization.data(withJSONObject: json))
}
@Test func notificationEventPolicyChecksFreshnessVisibilityAndQuietHours() throws {
    let now = VeraBotDate.parse("2026-10-14T02:00:00Z")!
    let fresh = try eventNote(created: now)
    #expect(NotificationEventPolicy.decision(fresh, settings: .init(), visibleMessageIDs: [], now: now, isForeground: true) == .banner)
    #expect(NotificationEventPolicy.decision(fresh, settings: .init(), visibleMessageIDs: [1], now: now, isForeground: true) == .silent)
    #expect(NotificationEventPolicy.decision(fresh, settings: .init(enabled: false), visibleMessageIDs: [], now: now, isForeground: false) == .silent)
    #expect(NotificationEventPolicy.decision(fresh, settings: .init(mutedBots: [8]), visibleMessageIDs: [], now: now, isForeground: false) == .silent)
    #expect(NotificationEventPolicy.decision(try eventNote(created: now.addingTimeInterval(-301)), settings: .init(), visibleMessageIDs: [], now: now, isForeground: true) == .silent)
    #expect(NotificationEventPolicy.decision(try eventNote(created: now, read: true), settings: .init(), visibleMessageIDs: [], now: now, isForeground: false) == .silent)
    let quiet = NotificationSettings(quietEnabled: true, quietStart: "09:00", quietEnd: "11:00", quietTimeZone: "Asia/Shanghai")
    #expect(NotificationEventPolicy.decision(fresh, settings: quiet, visibleMessageIDs: [], now: now, isForeground: true) == .silent)
    #expect(NotificationEventPolicy.decision(try eventNote(created: now, category: "reminder"), settings: .init(), visibleMessageIDs: [], now: now, isForeground: false) == .silent)
}
@Test func notificationEventLedgerPersistsBeforeAdvancingAndDeduplicates() throws {
    let now = Date()
    let note = try eventNote(created: now)
    let event = NotificationEvent(eventID: 1, notificationID: 1, operation: "created", notification: note)
    var ledger = NotificationEventLedger()
    ledger.ingest(NotificationEventPage(events: [event, event], nextCursor: 4, upperBound: 4, hasMore: false), now: now)
    #expect(ledger.cursor == 4 && ledger.pending.count == 1)
    let decoded = try JSONDecoder().decode(NotificationEventLedger.self, from: JSONEncoder().encode(ledger))
    #expect(decoded.pending.count == 1 && decoded.cursor == 4)
    ledger.finish(note, presented: true, now: now)
    ledger.ingest(NotificationEventPage(events: [event], nextCursor: 4, upperBound: 4, hasMore: false), now: now)
    #expect(ledger.pending.isEmpty)
    #expect(ledger.coalesces(note, now: now.addingTimeInterval(29)))
    #expect(!ledger.coalesces(note, now: now.addingTimeInterval(31)))
    #expect(ledger.needsBootstrap(now: now.addingTimeInterval(301)))
}
@Test func notificationEventUpdatesRemovePendingAndTaskResultDecodes() throws {
    let now = Date()
    let note = try eventNote(created: now, category: "task_result")
    #expect(note.category == .task_result)
    var ledger = NotificationEventLedger()
    let created = NotificationEvent(eventID: 1, notificationID: 1, operation: "created", notification: note)
    ledger.ingest(NotificationEventPage(events: [created], nextCursor: 1, upperBound: 1, hasMore: false), now: now)
    let deleted = NotificationEvent(eventID: 2, notificationID: 1, operation: "deleted", notification: nil)
    ledger.ingest(NotificationEventPage(events: [deleted], nextCursor: 2, upperBound: 2, hasMore: false), now: now)
    #expect(ledger.pending.isEmpty)
}
@Test func notificationReminderReconcilePreservesEventRequests() {
    let event = ScheduledLocalNotification(identifier: "vb.1.event.55", title: "消息", repeats: false)
    #expect(NotificationPlanner.reconcile(userID: 1, desired: [], existing: [event]).remove.isEmpty)
}

@Test func notificationTaskOutcomeDoesNotPresentFailureAsSuccess() throws {
    let now = Date()
    let json = "{\"id\":9,\"category\":\"task_result\",\"title\":\"任务执行失败\",\"source_state\":\"failed\",\"created_at\":\"\(VeraBotDate.format(now))\"}"
    let note = try JSONDecoder().decode(InboxNotification.self, from: Data(json.utf8))
    #expect(note.sourceState == "failed")
    #expect(note.taskNoticeState == .failure)
}

@Test func notificationDeliveryRetriesAreBoundedAndPersisted() throws {
    let now = Date(); let note = try eventNote(created: now)
    let event = NotificationEvent(eventID: 1, notificationID: 1, operation: "created", notification: note)
    var ledger = NotificationEventLedger()
    ledger.ingest(.init(events: [event], nextCursor: 1, upperBound: 1, hasMore: false), now: now)
    ledger.failed(note, now: now)
    #expect(!ledger.mayAttempt(note, now: now.addingTimeInterval(1)))
    #expect(ledger.mayAttempt(note, now: now.addingTimeInterval(6)))
    ledger.failed(note, now: now.addingTimeInterval(6))
    let restored = try JSONDecoder().decode(NotificationEventLedger.self, from: JSONEncoder().encode(ledger))
    #expect(!restored.mayAttempt(note, now: now.addingTimeInterval(7)))
    ledger.failed(note, now: now.addingTimeInterval(30))
    #expect(ledger.pending.isEmpty)
}

@Test func notificationBootstrapSnapshotRetainsOnlyValidDisplayedAlerts() throws {
    let now = Date()
    let notes = [try eventNote(id: 1, created: now), try eventNote(id: 2, created: now, read: true)]
    #expect(NotificationEventPolicy.retainedDisplayedIDs(notes, settings: .init(), now: now) == [1])
    #expect(NotificationEventPolicy.retainedDisplayedIDs(notes, settings: .init(enabled: false), now: now).isEmpty)
}

@Test func notificationOlderRefreshCannotOverwriteAcknowledgedAction() {
    var gate = NotificationRequestGate()
    let old = gate.begin(session: 1)
    let actionRefresh = gate.begin(session: 1)
    #expect(!gate.isCurrent(old, session: 1))
    #expect(gate.isCurrent(actionRefresh, session: 1))
    #expect(!gate.isCurrent(actionRefresh, session: 2))
}
