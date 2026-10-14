import Foundation
import Observation
import CryptoKit
import UserNotifications
import UIKit
import VeraBotCore
import VeraBotNetworking

@MainActor @Observable
final class NotificationEventSync {
    @ObservationIgnored private weak var app: AppState?
    @ObservationIgnored private weak var notices: BotNoticeCenter?
    @ObservationIgnored private var ledger = NotificationEventLedger()
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var forceBootstrap = true
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var syncOwner = UUID()
    private(set) var errorText: String?
    private(set) var settings = NotificationSettings()
    private(set) var scheduleErrorText: String?
    private(set) var pendingReminderCount = 0
    private(set) var reminderCoverageEnd: Date?
    var isForeground = true
    var visibleMessageIDs: Set<Int> = []
    var visibleBotID: Int?
    var visibleGroupID: Int?

    init(app: AppState) { self.app = app }
    func attach(_ notices: BotNoticeCenter) { self.notices = notices }
    func invalidate() {
        notices?.clear()
        settings = .init(); pendingReminderCount = 0; reminderCoverageEnd = nil; scheduleErrorText = nil
        forceBootstrap = true
        syncing = false; syncOwner = UUID()
        ledger = NotificationEventLedger(); scope = nil
        visibleMessageIDs = []; visibleBotID = nil; visibleGroupID = nil; errorText = nil
    }
    func updateReminderCoverage(count: Int, end: Date?, error: String?) {
        pendingReminderCount = count; reminderCoverageEnd = end
        scheduleErrorText = error == nil ? nil : "有提醒暂未排入系统，请稍后重试。"
    }
    func run() async {
        var failures = 0
        while !Task.isCancelled {
            do { try await syncOnce(); failures = 0 }
            catch is CancellationError { return }
            catch { failures = min(3, failures + 1); errorText = "通知暂未同步，联网后会继续更新。" }
            do { try await Task.sleep(for: .seconds([5, 15, 30, 60][failures])) }
            catch { return }
        }
    }
    private func fileURL(_ scope: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notification-events-\(scope).json")
    }
    private func save() throws {
        guard let scope else { return }
        let file = fileURL(scope)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ledger).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func reconcileDisplayed(api: any VeraBotAPI, userID: Int, now: Date) async throws {
        guard let app else { throw CancellationError() }
        let generation = app.sessionGeneration
        let sourceURL = app.baseURLString
        let ids = await NotificationCoordinator.shared.eventNotificationIDs(userID: userID).union(notices?.notificationIDs ?? [])
        var retained = Set<Int>()
        let list = Array(ids)
        for start in stride(from: 0, to: list.count, by: 200) {
            let notes = try await api.localNotificationState(ids: Array(list[start..<min(start + 200, list.count)]))
            try Task.checkCancellation()
            guard app.userID == userID, app.isCurrentSession(generation), app.baseURLString == sourceURL else { throw CancellationError() }
            retained.formUnion(NotificationEventPolicy.retainedDisplayedIDs(notes, settings: settings, now: now))
        }
        for id in ids.subtracting(retained) {
            try Task.checkCancellation()
            guard app.userID == userID, app.isCurrentSession(generation), app.baseURLString == sourceURL else { throw CancellationError() }
            await NotificationCoordinator.shared.removeEvent(notificationID: id, userID: userID)
            notices?.removeNotification(id)
        }
    }
    func syncOnce() async throws {
        guard !syncing, let app, let uid = app.userID, app.token != nil else { return }
        let owner = UUID(); syncOwner = owner; syncing = true
        defer { if syncOwner == owner { syncing = false } }
        let generation = app.sessionGeneration
        let baseURL = app.baseURLString
        let api = app.api
        func check() throws {
            try Task.checkCancellation()
            guard app.userID == uid, app.isCurrentSession(generation), app.baseURLString == baseURL, syncOwner == owner else { throw CancellationError() }
        }
        let server = SHA256.hash(data: Data(baseURL.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let currentScope = "\(server)-\(uid)-\(DeviceIdentity.current())"
        if scope != currentScope {
            scope = currentScope
            ledger = (try? JSONDecoder().decode(NotificationEventLedger.self, from: Data(contentsOf: fileURL(currentScope)))) ?? .init()
        }
        let prefs = try await api.notificationSettings()
        try check()
        if prefs != settings { await app.syncReminders(); try check() }
        settings = prefs
        NotificationCoordinator.shared.preferences = prefs
        let center = UNUserNotificationCenter.current()
        let permission = await center.notificationSettings().authorizationStatus
        try check()
        let deviceAllows = [.authorized, .provisional, .ephemeral].contains(permission)
        let now = Date()
        var bootstrapped = false
        if forceBootstrap || ledger.needsBootstrap(now: now) {
            let page = try await api.notificationEvents(after: nil, through: nil)
            try check(); try await reconcileDisplayed(api: api, userID: uid, now: now)
            try check(); ledger.bootstrap(cursor: page.nextCursor, now: now); try save(); bootstrapped = true; forceBootstrap = false
        } else {
            var through: Int?
            var more = true
            while more {
                let page = try await api.notificationEvents(after: ledger.cursor, through: through)
                try check()
                if page.resetRequired {
                    try await reconcileDisplayed(api: api, userID: uid, now: now); try check()
                    ledger.bootstrap(cursor: page.nextCursor, now: now); try save(); bootstrapped = true; forceBootstrap = false; break
                }
                ledger.ingest(page, now: now)
                try save() // cursor and pending events share an atomic write
                for event in page.events where event.operation == "deleted" || event.notification?.isUnread == false {
                    await NotificationCoordinator.shared.removeEvent(notificationID: event.notificationID, userID: uid)
                    try check(); notices?.removeNotification(event.notificationID)
                }
                through = page.upperBound; more = page.hasMore
            }
        }
        let summary = try await api.notificationSummary()
        try check(); app.unreadCount = summary.unreadCount
        if summary.pendingActionCount == 0 { notices?.remove(key: "notification:pending-tasks") }
        if bootstrapped, summary.pendingActionCount > 0, isForeground, settings.enabled,
           settings.categories["task_result"] == true, !NotificationEventPolicy.inQuietHours(settings, now: now) {
            notices?.show(BotNotice(title: "有 \(summary.pendingActionCount) 项任务需要你处理", tone: .confirmation,
                avatar: .awaitingConfirmation, actionTitle: "查看", duration: 5, link: "inbox"), key: "notification:pending-tasks")
        }
        try? await center.setBadgeCount(summary.unreadCount)
        try check()
        for event in ledger.pending {
            guard let note = event.notification, ledger.mayAttempt(note, now: now) else { continue }
            let foreground = isForeground && UIApplication.shared.applicationState == .active
            let modal = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController?.presentedViewController != nil
            let visible = foreground && app.selectedTab == 0 && notificationMatchesOpenConversation(note) && !modal ? visibleMessageIDs : []
            let decision = NotificationEventPolicy.decision(note, settings: settings, visibleMessageIDs: visible, now: now, isForeground: foreground)
            let coalesced = ledger.coalesces(note, now: now)
            var presented = false
            switch decision {
            case .silent: break
            case .banner:
                let hidden = note.sensitive || settings.preview == "none"
                let tone: BotNoticeTone
                if note.category == .task_result {
                    switch note.taskNoticeState {
                    case .success: tone = .success
                    case .failure: tone = .failure
                    case .warning: tone = .warning
                    case .awaitingConfirmation: tone = .confirmation
                    }
                } else { tone = .information }
                let notice = BotNotice(title: hidden ? "你有一条新通知" : note.title,
                    detail: hidden || settings.preview != "full" ? "" : note.body ?? "",
                    tone: tone, avatar: note.category == .task_result ? tone.avatar : .replying,
                    actionTitle: "查看", duration: 5, link: note.link)
                // Same conversation updates a visible notice during its 30-second aggregation window.
                notices?.show(notice, key: "notification:\(note.id)", replacing: coalesced)
                presented = true
                await app.report(notificationID: note.id, event: "presented_in_app", channel: "local")
            case .system:
                if deviceAllows {
                    do { try await NotificationCoordinator.shared.scheduleEvent(note, userID: uid, settings: settings, coalesced: coalesced) }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        try check(); ledger.failed(note, now: now); try save()
                        await app.report(notificationID: note.id, event: "failed", channel: "local")
                        continue
                    }
                    try check(); presented = true
                    await app.report(notificationID: note.id, event: "scheduled", channel: "local")
                }
            }
            try check(); ledger.finish(note, presented: presented, now: now); try save()
        }
        errorText = nil
    }

    /// 群消息和私聊消息各自编号，同一数字可能同时存在。只把当前打开的那一段对话里的 id 交给静音判断。
    private func notificationMatchesOpenConversation(_ note: InboxNotification) -> Bool {
        if let group = visibleGroupID {
            if note.threadId == "group:\(group)" { return true }
            if let link = note.link, link == "group/\(group)" || link.hasPrefix("group/\(group)/") { return true }
            return false
        }
        return visibleBotID == note.botId
    }
}
