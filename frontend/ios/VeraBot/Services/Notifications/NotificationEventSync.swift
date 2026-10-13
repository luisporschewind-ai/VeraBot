import Foundation
import Observation
import CryptoKit
import UserNotifications
import UIKit
import VeraBotCore

@MainActor @Observable
final class NotificationEventSync {
    @ObservationIgnored private weak var app: AppState?
    @ObservationIgnored private weak var notices: BotNoticeCenter?
    @ObservationIgnored private var ledger = NotificationEventLedger()
    @ObservationIgnored private var scope: String?
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

    init(app: AppState) { self.app = app }
    func attach(_ notices: BotNoticeCenter) { self.notices = notices }
    func invalidate() {
        syncing = false; syncOwner = UUID()
        ledger = NotificationEventLedger(); scope = nil
        visibleMessageIDs = []; visibleBotID = nil; errorText = nil
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
        if ledger.needsBootstrap(now: now) {
            let page = try await api.notificationEvents(after: nil, through: nil)
            try check(); ledger.bootstrap(cursor: page.nextCursor, now: now); try save()
        } else {
            var through: Int?
            var more = true
            while more {
                let page = try await api.notificationEvents(after: ledger.cursor, through: through)
                try check()
                if page.resetRequired { ledger.bootstrap(cursor: page.nextCursor, now: now); try save(); break }
                ledger.ingest(page, now: now)
                try save() // cursor and pending events share an atomic write
                for event in page.events where event.operation == "deleted" || event.notification?.isUnread == false {
                    await NotificationCoordinator.shared.removeEvent(notificationID: event.notificationID, userID: uid)
                    if notices?.current?.key == "notification:\(event.notificationID)", let id = notices?.current?.id { notices?.dismiss(id: id) }
                }
                through = page.upperBound; more = page.hasMore
            }
        }
        let summary = try await api.notificationSummary()
        try check(); app.unreadCount = summary.unreadCount
        try? await center.setBadgeCount(summary.unreadCount)
        try check()
        for event in ledger.pending {
            guard let note = event.notification, ledger.mayAttempt(note, now: now) else { continue }
            let foreground = isForeground && UIApplication.shared.applicationState == .active
            let modal = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController?.presentedViewController != nil
            let visible = foreground && app.selectedTab == 0 && visibleBotID == note.botId && !modal ? visibleMessageIDs : []
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
}
