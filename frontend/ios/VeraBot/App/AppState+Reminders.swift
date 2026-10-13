import Foundation
import UserNotifications
import VeraBotCore
import VeraBotNetworking

extension AppState {
    func syncReminders() async {
        guard token != nil, let userID else { return }
        let generation = sessionGeneration
        await replayOutbox()
        guard isCurrentSession(generation) else { return }
        do {
            async let list = api.reminders()
            async let summary = api.notificationSummary()
            async let settings = api.notificationSettings()
            let (reminders, badge, prefs) = try await (list, summary, settings)
            guard isCurrentSession(generation) else { return }
            unreadCount = badge.unreadCount
            let permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            guard isCurrentSession(generation) else { return }
            let allowed = [.authorized, .provisional, .ephemeral].contains(permission)
            var localPrefs = prefs; localPrefs.enabled = prefs.enabled && allowed
            let overrides = ReminderOutboxStore.load(userID: userID).map(ReminderLocalOverride.init)
            let planned = NotificationPlanner.plan(userID: userID, reminders: reminders.reminders, preview: prefs.preview,
                settings: localPrefs, overrides: overrides)
            NotificationCoordinator.shared.preferences = prefs
            await NotificationCoordinator.shared.apply(planned: planned, userID: userID)
            let (count, end) = await NotificationCoordinator.shared.reminderCoverage(userID: userID)
            guard isCurrentSession(generation) else { return }
            notificationEvents.updateReminderCoverage(count: count, end: end, error: NotificationCoordinator.shared.lastScheduleError)
            _ = try? await api.registerDevice(currentDevice(localReminders: allowed && prefs.enabled && prefs.categories["reminder"] == true, localEvents: allowed))
        } catch {
            if let error = error as? APIError, error.status == 401, isCurrentSession(generation) {
                signOut()
            }
        }
    }

    func open(link: String) async {
        guard token != nil else { return }
        let generation = sessionGeneration
        let sourceURL = baseURLString
        let reminders = (try? await api.reminders().reminders.map(\.id)) ?? []
        let bots = (try? await api.bots().bots.map(\.id)) ?? []
        let plugins = (try? await api.plugins().plugins.map(\.pluginId)) ?? []
        guard isCurrentSession(generation), baseURLString == sourceURL else { return }
        switch DeepLinkRouter.resolve(link, reminderIDs: Set(reminders), botIDs: Set(bots), pluginIDs: Set(plugins)) {
        case .missing:
            missingNotice = "内容已不存在"
        case .navigate(let destination):
            switch destination {
            case .chat:
                selectedTab = 0
            case .plugin:
                selectedTab = 0
            case .notificationSettings:
                showNotificationSettings = true
            case .reminder, .reminders, .inbox:
                selectedTab = 1
            }
            pendingLink = destination
        }
    }

    func performReminderAction(reminderID: Int, action: String, minutes: Int?, idempotencyKey: String) async {
        guard let userID else { return }
        let generation = sessionGeneration
        let until = action == "snooze" ? VeraBotDate.format(Date().addingTimeInterval(Double(minutes ?? 10) * 60)) : nil
        let item = ReminderOutboxItem(idempotencyKey: idempotencyKey, reminderID: reminderID, action: action, minutes: nil, until: until)
        ReminderOutboxStore.save(userID: userID, items: ReminderOutbox.appending(item, to: ReminderOutboxStore.load(userID: userID)))
        if action == "snooze" {
            await NotificationCoordinator.shared.scheduleSnooze(userID: userID, reminderID: reminderID, title: "稍后提醒", until: VeraBotDate.parse(until) ?? Date().addingTimeInterval(600))
        } else { await NotificationCoordinator.shared.removeReminder(reminderID, userID: userID) }
        guard isCurrentSession(generation) else { return }
        Task { [weak self] in
            guard let self, self.isCurrentSession(generation) else { return }
            await self.syncReminders()
        }
    }

    func report(notificationID: Int, event: String, channel: String) async {
        _ = try? await api.reportNotification(id: notificationID, event: event, channel: channel, deviceId: DeviceIdentity.current())
    }

    func replayOutbox() async {
        guard let userID else { return }
        let generation = sessionGeneration
        var items = ReminderOutboxStore.load(userID: userID)
        var dropped = 0
        var kept: [ReminderOutboxItem] = []
        for item in items {
            guard isCurrentSession(generation) else { return }
            if item.action == "snooze", let until = VeraBotDate.parse(item.until), until <= Date() { dropped += 1; continue }
            do {
                if item.action == "snooze" {
                    _ = try await api.snoozeReminder(item.reminderID, minutes: item.until == nil ? item.minutes : nil, until: item.until,
                                                    idempotencyKey: item.idempotencyKey)
                } else {
                    _ = try await api.completeReminder(item.reminderID, idempotencyKey: item.idempotencyKey)
                }
            } catch let error as APIError where ReminderOutbox.shouldDrop(status: error.status, code: error.code) {
                if error.code == "version_conflict" { dropped += 1 }
            } catch {
                kept.append(item)
            }
        }
        guard isCurrentSession(generation) else { return }
        let attempted = Set(items.map(\.idempotencyKey))
        kept += ReminderOutboxStore.load(userID: userID).filter { !attempted.contains($0.idempotencyKey) }
        items = kept
        if items.isEmpty {
            ReminderOutboxStore.remove(userID: userID)
        } else {
            ReminderOutboxStore.save(userID: userID, items: items)
        }
        if dropped > 0 {
            missingNotice = "有 \(dropped) 项操作因提醒已在别处修改而未生效"
        }
    }

    private func currentDevice(localReminders: Bool, localEvents: Bool) -> DeviceRegistration {
        DeviceRegistration(deviceId: DeviceIdentity.current(), platform: "ios", apnsToken: nil, apnsEnv: nil,
                           appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                           osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                           timezone: TimeZone.current.identifier, localReminders: localReminders, localEvents: localEvents)
    }
}
