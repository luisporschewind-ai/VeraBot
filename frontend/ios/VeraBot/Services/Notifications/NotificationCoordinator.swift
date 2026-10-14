import Foundation
import CryptoKit
import UserNotifications
import VeraBotCore

extension Notification.Name {
    static let verabotRemindersChanged = Notification.Name("verabotRemindersChanged")
}

enum ReminderOutboxStore {
    static func url(userID: Int, server: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(ReminderOutbox.fileName(userID: userID, server: server))
    }

    static func load(userID: Int, server: String) -> [ReminderOutboxItem] {
        guard let data = try? Data(contentsOf: url(userID: userID, server: server)) else { return [] }
        return ReminderOutbox.decode(data)
    }

    static func save(userID: Int, server: String, items: [ReminderOutboxItem]) {
        let file = url(userID: userID, server: server)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ReminderOutbox.encode(items).write(to: file, options: .atomic)
    }

    static func remove(userID: Int, server: String) {
        try? FileManager.default.removeItem(at: url(userID: userID, server: server))
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
    let sourceURL: String?
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
    var preferences = NotificationSettings()
    private var pendingTap: NotificationTap?
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
        let generic = UNNotificationCategory(identifier: "VB_GENERIC", actions: [], intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories([category, generic])
    }

    func requestReminderAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func clearAll() {
        revision += 1
        pendingTap = nil
        preferences = .init()
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0) { _ in }
    }

    func apply(planned: [PlannedNotification], userID: Int, validReminderIDs: Set<Int>, request: NotificationRequestToken) async {
        let previous = schedulingTail
        let revision = revision
        let generation = app?.sessionGeneration
        let work = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.revision == revision, self.app?.isCurrentReminderRequest(request) == true, self.app?.userID == userID,
                  self.app?.sessionGeneration == generation else { return }
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            guard self.revision == revision, self.app?.isCurrentReminderRequest(request) == true, self.app?.sessionGeneration == generation else { return }
            let existing = pending.map {
                ScheduledLocalNotification(identifier: $0.identifier, title: $0.content.title,
                    repeats: $0.trigger?.repeats ?? false, signature: $0.content.userInfo["source_url"] as? String == self.app?.baseURLString ? $0.content.userInfo["signature"] as? String : nil)
            }
            let diff = NotificationPlanner.reconcile(userID: userID, desired: planned, existing: existing)
            center.removePendingNotificationRequests(withIdentifiers: diff.remove)
            center.removeDeliveredNotifications(withIdentifiers: NotificationPlanner.cancelDelivered(
                userID: userID, validReminderIDs: validReminderIDs, identifiers: delivered.map { $0.request.identifier }))
            self.lastScheduleError = nil
            for item in diff.add {
                guard self.revision == revision, self.app?.isCurrentReminderRequest(request) == true, self.app?.sessionGeneration == generation else { return }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.sound = item.soundEnabled ? .default : nil
                content.categoryIdentifier = "VB_REMINDER"
                content.userInfo = ["source_url": self.app?.baseURLString ?? "", "uid": item.userID, "link": "reminder/\(item.reminderID)",
                                    "reminder_id": item.reminderID, "signature": item.signature]
                guard let trigger = self.trigger(for: item, calendar: Calendar.current) else { continue }
                do { try await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)) }
                catch { self.lastScheduleError = error.localizedDescription }
                if self.revision != revision || self.app?.sessionGeneration != generation || self.app?.isCurrentReminderRequest(request) != true {
                    center.removePendingNotificationRequests(withIdentifiers: [item.identifier]); return
                }
            }
        }
        schedulingTail = work
        await work.value
    }

    func scheduleSnooze(userID: Int, reminderID: Int, title: String, until: Date) async {
        let previous = schedulingTail
        let revision = revision
        let generation = app?.sessionGeneration
        let work = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.app?.userID == userID, self.app?.sessionGeneration == generation, self.revision == revision else { return }
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            guard self.app?.sessionGeneration == generation, self.revision == revision else { return }
            let prefix = "vb.\(userID).rem.\(reminderID)."
            let ids = (pending + delivered.map(\.request)).map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
            let permission = await center.notificationSettings().authorizationStatus
            guard self.app?.sessionGeneration == generation, self.revision == revision,
                  self.preferences.enabled, self.preferences.categories["reminder"] == true,
                  [.authorized, .provisional, .ephemeral].contains(permission) else { return }
            var item = PlannedNotification(identifier: prefix + "\(Int(until.timeIntervalSince1970))", reminderID: reminderID,
                userID: userID, title: title, fireDate: until, repeats: false)
            item.soundEnabled = self.preferences.soundEnabled
            let content = UNMutableNotificationContent()
            content.title = title; content.sound = item.soundEnabled ? .default : nil; content.categoryIdentifier = "VB_REMINDER"
            content.userInfo = ["source_url": self.app?.baseURLString ?? "", "uid": userID, "reminder_id": reminderID, "link": "reminder/\(reminderID)", "signature": item.signature]
            guard let trigger = self.trigger(for: item, calendar: .current) else { return }
            do { try await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)) }
            catch { self.lastScheduleError = error.localizedDescription }
            if self.app?.sessionGeneration != generation || self.revision != revision {
                center.removePendingNotificationRequests(withIdentifiers: [item.identifier])
            }
        }
        schedulingTail = work; await work.value
    }

    func removeReminder(_ id: Int, userID: Int) async {
        let previous = schedulingTail
        let revision = revision
        let generation = app?.sessionGeneration
        let work = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.app?.userID == userID, self.app?.sessionGeneration == generation, self.revision == revision else { return }
            let center = UNUserNotificationCenter.current()
            let requests = await center.pendingNotificationRequests()
            let delivered = await center.deliveredNotifications()
            guard self.app?.sessionGeneration == generation, self.revision == revision else { return }
            let prefix = "vb.\(userID).rem.\(id)."
            let ids = (requests + delivered.map(\.request)).map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
        schedulingTail = work; await work.value
    }

    func reminderCoverage(userID: Int) async -> (Int, Date?) {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests().filter { $0.identifier.hasPrefix("vb.\(userID).rem.") }
        let dates: [Date] = requests.filter { $0.trigger?.repeats != true }.compactMap {
            if let trigger = $0.trigger as? UNTimeIntervalNotificationTrigger { return trigger.nextTriggerDate() }
            if let trigger = $0.trigger as? UNCalendarNotificationTrigger { return trigger.nextTriggerDate() }
            return nil
        }
        return (requests.count, dates.max())
    }

    // 用「completionHandler」版本的代理方法，不用 async 版本：
    // async 版本由编译器生成的 @objc thunk 在协作线程池里调用系统的 completionHandler，
    // UIKit 随后在该线程更新快照 / 状态恢复（-[UIApplication _updateSnapshotAndStateRestorationWithAction:]），
    // 触发「必须在主线程」断言崩溃（.ips 2026-10-03 20:22 / 20:37）。
    // 这里先在 nonisolated 方法里取出 Sendable 的值，再回主线程处理，并在主线程调用 completionHandler。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        let sourceURL = info["source_url"] as? String
        let uid = info["uid"] as? Int
        let nid = info["nid"] as? Int
        let done = MainThreadCallback(completionHandler)
        Task { @MainActor in
            let options = await self.handleWillPresent(uid: uid, nid: nid, sourceURL: sourceURL)
            done.call(options)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        let info = request.content.userInfo
        let tap = NotificationTap(
            sourceURL: info["source_url"] as? String, uid: info["uid"] as? Int, reminderID: info["reminder_id"] as? Int, nid: info["nid"] as? Int,
            link: info["link"] as? String, identifier: request.identifier,
            actionIdentifier: response.actionIdentifier, title: request.content.title
        )
        let done = MainThreadCallback<Void> { _ in completionHandler() }
        Task { @MainActor in
            await self.handleResponse(tap)
            done.call(())
        }
    }

    private func handleWillPresent(uid: Int?, nid: Int?, sourceURL: String?) async -> UNNotificationPresentationOptions {
        guard let app, let uid, uid == app.userID, sourceURL == app.baseURLString, preferences.enabled else { return [] }
        if nid == nil && preferences.categories["reminder"] != true { return [] }
        if let nid {
            await app.report(notificationID: nid, event: "delivered", channel: "local")
        }
        return preferences.soundEnabled ? [.banner, .sound, .list] : [.banner, .list]
    }

    private func handleResponse(_ tap: NotificationTap) async {
        let center = UNUserNotificationCenter.current()
        let uid = tap.uid
        guard let app, app.token != nil else { pendingTap = tap; return }
        guard uid == app.userID, tap.sourceURL == app.baseURLString else {
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

    func resumePendingTap() async {
        guard app?.token != nil, let tap = pendingTap else { return }
        pendingTap = nil
        await handleResponse(tap)
    }

    func scheduleEvent(_ note: InboxNotification, userID: Int, settings: NotificationSettings, coalesced: Bool) async throws {
        let previous = schedulingTail
        let revision = revision
        let generation = app?.sessionGeneration
        let digest = SHA256.hash(data: Data(note.localThreadKey.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let identifier = "vb.\(userID).event.\(digest)"
        let work = Task { @MainActor [weak self] () -> Result<Void, Error> in
            await previous?.value
            guard let self, self.app?.userID == userID, self.app?.sessionGeneration == generation, self.revision == revision else { return .failure(CancellationError()) }
            let content = UNMutableNotificationContent()
            let hidden = note.sensitive || settings.preview == "none"
            content.title = hidden ? "你有一条新通知" : note.title
            content.body = hidden || settings.preview != "full" ? "" : note.body ?? ""
            content.sound = settings.soundEnabled && !coalesced ? .default : nil
            content.categoryIdentifier = "VB_GENERIC"
            content.threadIdentifier = note.localThreadKey
            content.userInfo = ["source_url": self.app?.baseURLString ?? "", "uid": userID, "nid": note.id, "link": note.link ?? "inbox"]
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
                if self.app?.sessionGeneration != generation || self.revision != revision {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
                    return .failure(CancellationError())
                }
                return .success(())
            } catch { return .failure(error) }
        }
        schedulingTail = Task { _ = await work.value }
        try await work.value.get()
    }

    func eventNotificationIDs(userID: Int) async -> Set<Int> {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        return Set((pending + delivered.map(\.request)).compactMap {
            $0.content.userInfo["uid"] as? Int == userID ? $0.content.userInfo["nid"] as? Int : nil
        })
    }

    func removeEvent(notificationID: Int, userID: Int) async {
        let center = UNUserNotificationCenter.current()
        let generation = app?.sessionGeneration
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        guard app?.userID == userID, app?.sessionGeneration == generation else { return }
        let requests = pending + delivered.map(\.request)
        let ids = requests.filter { $0.content.userInfo["nid"] as? Int == notificationID && $0.content.userInfo["uid"] as? Int == userID }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
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
