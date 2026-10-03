import SwiftUI
import UIKit
import UserNotifications
import VeraBotCore
import VeraBotNetworking

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.notificationsEnabled) private var notificationsEnabled = false
    @State private var settings = NotificationSettings()
    @State private var bots: [Bot] = []
    @State private var quietStart = Date()
    @State private var quietEnd = Date()
    @State private var showDeniedAlert = false
    @State private var errorText: String?
    @State private var loaded = false

    var body: some View {
        ThemedForm {
            Section {
                CompactToggle(isOn: $notificationsEnabled) {
                    Label("允许通知", systemImage: "bell.badge")
                }
                .onChange(of: notificationsEnabled) { _, isOn in
                    if isOn {
                        Task { await requestAuthorization() }
                    } else {
                        settings.enabled = false
                        Task { await save() }
                    }
                }
            } footer: {
                Text("系统不允许时，通知只会留在收件箱。")
            }
            Section("分类") {
                categoryToggle("提醒", key: "reminder")
                categoryToggle("Bot 消息", key: "bot_message")
                categoryToggle("协作完成", key: "delegation")
                categoryToggle("插件", key: "plugin")
                LabeledContent("系统") { Text("安全通知不能关闭").font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                Toggle("免打扰", isOn: $settings.quietEnabled)
                    .onChange(of: settings.quietEnabled) { _, _ in Task { await save() } }
                DatePicker("开始", selection: $quietStart, displayedComponents: .hourAndMinute)
                    .onChange(of: quietStart) { _, value in
                        settings.quietStart = clock(value)
                        Task { await save() }
                    }
                DatePicker("结束", selection: $quietEnd, displayedComponents: .hourAndMinute)
                    .onChange(of: quietEnd) { _, value in
                        settings.quietEnd = clock(value)
                        Task { await save() }
                    }
            } footer: {
                Text("提醒不受免打扰影响。")
            }
            Section {
                Picker("通知显示内容", selection: $settings.preview) {
                    Text("显示完整内容").tag("full")
                    Text("仅标题").tag("title")
                    Text("不显示内容").tag("none")
                }
                .onChange(of: settings.preview) { _, _ in Task { await save() } }
            }
            Section("已静音的 Bot") {
                let muted = bots.filter { settings.mutedBots.contains($0.id) }
                if muted.isEmpty {
                    Text("没有静音的 Bot").foregroundStyle(.secondary)
                }
                ForEach(muted) { bot in
                    Button("取消静音 \(bot.name)") { Task { await unmute(bot.id) } }
                }
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await syncSystemStatus() } }
        }
        .alert("通知权限已关闭", isPresented: $showDeniedAlert) {
            Button("前往设置") { openNotificationSettings() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在系统设置中允许 Vera Bot 发送通知。")
        }
    }

    private func categoryToggle(_ title: String, key: String) -> some View {
        CompactToggle(isOn: Binding(get: { settings.categories[key] ?? false }, set: { on in
            settings.categories[key] = on
            Task { await save() }
        })) {
            Text(title)
        }
    }

    private func load() async {
        do {
            settings = try await app.api.notificationSettings()
            bots = try await app.api.bots().bots
            quietStart = parse(settings.quietStart)
            quietEnd = parse(settings.quietEnd)
            notificationsEnabled = settings.enabled
            loaded = true
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
        await syncSystemStatus()
    }

    private func save() async {
        guard loaded else { return }
        settings.enabled = notificationsEnabled
        settings.quietTimeZone = TimeZone.current.identifier
        do {
            settings = try await app.api.updateNotificationSettings(settings)
            await app.syncReminders()
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func unmute(_ id: Int) async {
        settings.mutedBots.removeAll { $0 == id }
        await save()
    }

    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            settings.enabled = true
            await save()
        case .denied:
            notificationsEnabled = false
            showDeniedAlert = true
        default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            notificationsEnabled = granted
            if granted {
                settings.enabled = true
                await save()
            } else {
                showDeniedAlert = true
            }
        }
    }

    private func syncSystemStatus() async {
        guard notificationsEnabled else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .denied { notificationsEnabled = false }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }

    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func parse(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: text) ?? Date()
    }
}
