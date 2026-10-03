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

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    private weak var app: AppState?

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
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0) { _ in }
    }

    func apply(planned: [PlannedNotification], userID: Int) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existing = pending.map {
            ScheduledLocalNotification(identifier: $0.identifier, title: $0.content.title, repeats: $0.trigger?.repeats ?? false)
        }
        let diff = NotificationPlanner.reconcile(userID: userID, desired: planned, existing: existing)
        if !diff.remove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.remove)
        }
        let calendar = Calendar.current
        for item in diff.add {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.sound = .default
            content.categoryIdentifier = "VB_REMINDER"
            content.userInfo = [
                "uid": item.userID,
                "link": "reminder/\(item.reminderID)",
                "reminder_id": item.reminderID,
            ]
            guard let trigger = trigger(for: item, calendar: calendar) else { continue }
            let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func scheduleSnooze(userID: Int, reminderID: Int, title: String) async {
        let fire = Date().addingTimeInterval(10 * 60)
        let epoch = Int(fire.timeIntervalSince1970)
        let item = PlannedNotification(identifier: "vb.\(userID).rem.\(reminderID).\(epoch)", reminderID: reminderID,
                                       userID: userID, title: title, fireDate: fire, repeats: false)
        await apply(planned: [item], userID: userID)
    }

    func removeReminder(_ id: Int, userID: Int) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let prefix = "vb.\(userID).rem.\(id)."
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if let app, let uid = notification.request.content.userInfo["uid"] as? Int, uid != app.userID {
            return []
        }
        if let nid = notification.request.content.userInfo["nid"] as? Int {
            await app?.report(notificationID: nid, event: "delivered", channel: "local")
        }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let uid = info["uid"] as? Int
        guard let app, uid == app.userID else {
            center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
            center.removePendingNotificationRequests(withIdentifiers: [response.notification.request.identifier])
            return
        }
        let reminderID = info["reminder_id"] as? Int
        let identifier = response.notification.request.identifier
        switch response.actionIdentifier {
        case "VB_DONE":
            if let reminderID {
                await removeReminder(reminderID, userID: app.userID ?? uid ?? 0)
                await app.performReminderAction(reminderID: reminderID, action: "complete", minutes: nil,
                                                idempotencyKey: identifier + ":done")
            }
        case "VB_SNOOZE_10":
            if let reminderID {
                await scheduleSnooze(userID: app.userID ?? uid ?? 0, reminderID: reminderID,
                                     title: response.notification.request.content.title)
                await app.performReminderAction(reminderID: reminderID, action: "snooze", minutes: 10,
                                                idempotencyKey: identifier + ":snooze")
            }
        case UNNotificationDismissActionIdentifier:
            if let nid = info["nid"] as? Int {
                await app.report(notificationID: nid, event: "dismissed", channel: "local")
            }
        default:
            if let link = info["link"] as? String {
                await app.open(link: link)
            }
            if let nid = info["nid"] as? Int {
                await app.report(notificationID: nid, event: "opened", channel: "local")
            }
        }
    }

    private func trigger(for item: PlannedNotification, calendar: Calendar) -> UNNotificationTrigger? {
        if item.repeats {
            var parts = DateComponents()
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
