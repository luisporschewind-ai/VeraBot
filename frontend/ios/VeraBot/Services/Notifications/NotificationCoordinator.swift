import Foundation
import UserNotifications
import VeraBotCore

extension Notification.Name {
    static let verabotRemindersChanged = Notification.Name("verabotRemindersChanged")
}

enum ReminderOutboxStore {
    static func url(userID: Int) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(ReminderOutbox.fileName(userID: userID))
    }

    static func load(userID: Int) -> [ReminderOutboxItem] {
        guard let data = try? Data(contentsOf: url(userID: userID)) else { return [] }
        return ReminderOutbox.decode(data)
    }

    static func save(userID: Int, items: [ReminderOutboxItem]) {
        let file = url(userID: userID)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ReminderOutbox.encode(items).write(to: file, options: .atomic)
    }

    static func remove(userID: Int) {
        try? FileManager.default.removeItem(at: url(userID: userID))
    }
}

/// 系统交给代理的 completionHandler（ObjC 块，未标 Sendable）。
/// 只在主线程（MainActor）上调用，所以可以安全地跨线程带过去。
private struct MainThreadCallback<Value>: @unchecked Sendable {
    let body: (Value) -> Void
    init(_ body: @escaping (Value) -> Void) { self.body = body }
    @MainActor func call(_ value: Value) { body(value) }
}

/// 通知代理回调里取出的值（Sendable），交给主线程处理。
struct NotificationTap: Sendable {
    let uid: Int?
    let reminderID: Int?
    let nid: Int?
    let link: String?
    let identifier: String
    let actionIdentifier: String
    let title: String
}

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    private weak var app: AppState?
    private var revision = 0
    private var schedulingTail: Task<Void, Never>?
    private(set) var lastScheduleError: String?

    func start(app: AppState) {
        self.app = app
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "VB_DONE", title: "完成", options: [])
        let snooze = UNNotificationAction(identifier: "VB_SNOOZE_10", title: "稍后 10 分钟", options: [])
        let category = UNNotificationCategory(identifier: "VB_REMINDER", actions: [done, snooze],
                                              intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories([category])
    }

    func clearAll() {
        revision += 1
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0) { _ in }
    }

    func apply(planned: [PlannedNotification], userID: Int) async {
        let previous = schedulingTail
        let revision = revision
        let generation = app?.sessionGeneration
        let work = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.revision == revision, self.app?.userID == userID,
                  self.app?.sessionGeneration == generation else { return }
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard self.revision == revision, self.app?.sessionGeneration == generation else { return }
            let existing = pending.map {
                ScheduledLocalNotification(identifier: $0.identifier, title: $0.content.title,
                    repeats: $0.trigger?.repeats ?? false, signature: $0.content.userInfo["signature"] as? String)
            }
            let diff = NotificationPlanner.reconcile(userID: userID, desired: planned, existing: existing)
            center.removePendingNotificationRequests(withIdentifiers: diff.remove)
            self.lastScheduleError = nil
            for item in diff.add {
                guard self.revision == revision, self.app?.sessionGeneration == generation else { return }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.sound = .default
                content.categoryIdentifier = "VB_REMINDER"
                content.userInfo = ["uid": item.userID, "link": "reminder/\(item.reminderID)",
                                    "reminder_id": item.reminderID, "signature": item.signature]
                guard let trigger = self.trigger(for: item, calendar: Calendar.current) else { continue }
                do { try await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)) }
                catch { self.lastScheduleError = error.localizedDescription }
                if self.revision != revision || self.app?.sessionGeneration != generation {
                    center.removePendingNotificationRequests(withIdentifiers: [item.identifier]); return
                }
            }
        }
        schedulingTail = work
        await work.value
    }

    func scheduleSnooze(userID: Int, reminderID: Int, title: String) async {
        let fire = Date().addingTimeInterval(10 * 60)
        let epoch = Int(fire.timeIntervalSince1970)
        let item = PlannedNotification(identifier: "vb.\(userID).rem.\(reminderID).\(epoch)", reminderID: reminderID,
                                       userID: userID, title: title, fireDate: fire, repeats: false)
        // A snooze is a targeted update, never a full desired set.
        await removeReminder(reminderID, userID: userID)
        guard app?.userID == userID else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.sound = .default; content.categoryIdentifier = "VB_REMINDER"
        content.userInfo = ["uid": userID, "reminder_id": reminderID, "link": "reminder/\(reminderID)", "signature": item.signature]
        guard let trigger = trigger(for: item, calendar: .current) else { return }
        let generation = app?.sessionGeneration
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)) }
        catch { lastScheduleError = error.localizedDescription }
        if app?.sessionGeneration != generation { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [item.identifier]) }
    }

    func removeReminder(_ id: Int, userID: Int) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let prefix = "vb.\(userID).rem.\(id)."
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // 用「completionHandler」版本的代理方法，不用 async 版本：
    // async 版本由编译器生成的 @objc thunk 在协作线程池里调用系统的 completionHandler，
    // UIKit 随后在该线程更新快照 / 状态恢复（-[UIApplication _updateSnapshotAndStateRestorationWithAction:]），
    // 触发「必须在主线程」断言崩溃（.ips 2026-10-03 20:22 / 20:37）。
    // 这里先在 nonisolated 方法里取出 Sendable 的值，再回主线程处理，并在主线程调用 completionHandler。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        let uid = info["uid"] as? Int
        let nid = info["nid"] as? Int
        let done = MainThreadCallback(completionHandler)
        Task { @MainActor in
            let options = await self.handleWillPresent(uid: uid, nid: nid)
            done.call(options)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        let info = request.content.userInfo
        let tap = NotificationTap(
            uid: info["uid"] as? Int, reminderID: info["reminder_id"] as? Int, nid: info["nid"] as? Int,
            link: info["link"] as? String, identifier: request.identifier,
            actionIdentifier: response.actionIdentifier, title: request.content.title
        )
        let done = MainThreadCallback<Void> { _ in completionHandler() }
        Task { @MainActor in
            await self.handleResponse(tap)
            done.call(())
        }
    }

    private func handleWillPresent(uid: Int?, nid: Int?) async -> UNNotificationPresentationOptions {
        if let app, let uid, uid != app.userID {
            return []
        }
        if let nid {
            await app?.report(notificationID: nid, event: "delivered", channel: "local")
        }
        return [.banner, .sound, .list]
    }

    private func handleResponse(_ tap: NotificationTap) async {
        let center = UNUserNotificationCenter.current()
        let uid = tap.uid
        guard let app, uid == app.userID else {
            center.removeDeliveredNotifications(withIdentifiers: [tap.identifier])
            center.removePendingNotificationRequests(withIdentifiers: [tap.identifier])
            return
        }
        let reminderID = tap.reminderID
        let identifier = tap.identifier
        switch tap.actionIdentifier {
        case "VB_DONE":
            if let reminderID {
                await app.performReminderAction(reminderID: reminderID, action: "complete", minutes: nil,
                                                idempotencyKey: identifier + ":done")
            }
        case "VB_SNOOZE_10":
            if let reminderID {
                await app.performReminderAction(reminderID: reminderID, action: "snooze", minutes: 10,
                                                idempotencyKey: identifier + ":snooze")
            }
        case UNNotificationDismissActionIdentifier:
            if let nid = tap.nid {
                await app.report(notificationID: nid, event: "dismissed", channel: "local")
            }
        default:
            if let link = tap.link {
                await app.open(link: link)
            }
            if let nid = tap.nid {
                await app.report(notificationID: nid, event: "opened", channel: "local")
            }
        }
    }

    private func trigger(for item: PlannedNotification, calendar: Calendar) -> UNNotificationTrigger? {
        if item.repeats {
            var calendar = calendar
            calendar.timeZone = TimeZone(identifier: item.timeZone) ?? .gmt
            var parts = DateComponents()
            parts.calendar = calendar
            parts.timeZone = calendar.timeZone
            parts.hour = calendar.component(.hour, from: item.fireDate)
            parts.minute = calendar.component(.minute, from: item.fireDate)
            if let weekday = item.weekday {
                parts.weekday = weekday == 7 ? 1 : weekday + 1
            } else if item.identifier.hasSuffix(".weekly") {
                parts.weekday = calendar.component(.weekday, from: item.fireDate)
            }
            return UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        }
        let interval = item.fireDate.timeIntervalSinceNow
        guard interval > 1 else { return nil }
        return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    }
}
