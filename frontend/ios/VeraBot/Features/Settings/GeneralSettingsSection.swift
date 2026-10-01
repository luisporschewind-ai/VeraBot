import SwiftUI
import UIKit
import UserNotifications
import VeraBotCore

/// 通用：外观 / 通知 / 触感反馈 / 语言。均为系统原生控件，偏好存 @AppStorage（SettingsKeys）。
struct GeneralSettingsSection: View {
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(SettingsKeys.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(SettingsKeys.hapticsEnabled) private var hapticsEnabled = true
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDeniedAlert = false

    var body: some View {
        Section {
            Picker(selection: $appearanceRaw) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            } label: {
                Label("外观", systemImage: "circle.lefthalf.filled")
            }

            CompactToggle(isOn: $notificationsEnabled) {
                Label("通知", systemImage: "bell.badge")
            }
            .onChange(of: notificationsEnabled) { _, isOn in
                if isOn { Task { await requestAuthorization() } }
            }

            CompactToggle(isOn: $hapticsEnabled) {
                Label("触感反馈", systemImage: "hand.tap")
            }

            Button {
                openAppSettings()
            } label: {
                LabeledContent {
                    Text(currentLanguage).foregroundStyle(.secondary)
                } label: {
                    Label {
                        Text("语言").foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "globe")
                    }
                }
            }
        } header: {
            Text("通用")
        } footer: {
            Text("语言在系统「设置」中按 App 单独切换。")
        }
        .task { await syncNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await syncNotificationStatus() } }   // 从系统设置返回后同步授权状态
        }
        .alert("通知权限已关闭", isPresented: $showDeniedAlert) {
            Button("前往设置") { openNotificationSettings() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在系统设置中允许 Vera Bot 发送通知。")
        }
    }

    /// 当前 App 实际使用的界面语言（系统按 App 语言设置选出的本地化）
    private var currentLanguage: String {
        let id = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return Locale(identifier: "zh-Hans").localizedString(forIdentifier: id) ?? id
    }

    private func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            denied()
        default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if !granted { denied() }
        }
    }

    /// 开关开着但系统授权已被关闭时，回退开关，保持与系统一致
    private func syncNotificationStatus() async {
        guard notificationsEnabled else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status == .denied { notificationsEnabled = false }
    }

    private func denied() {
        notificationsEnabled = false
        showDeniedAlert = true
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}
