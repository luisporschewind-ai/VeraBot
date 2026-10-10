import SwiftUI
import UIKit
import VeraBotCore

/// 通用：外观 / 通知 / 触感反馈 / 语言。均为系统原生控件，偏好存 @AppStorage（SettingsKeys）。
struct GeneralSettingsSection: View {
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(SettingsKeys.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKeys.quickPromptsEnabled) private var quickPromptsEnabled = SettingsKeys.quickPromptsEnabledDefault
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Picker(selection: $appearanceRaw) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            } label: {
                Label("外观", systemImage: "circle.lefthalf.filled")
            }

            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label("通知", systemImage: "bell.badge")
            }

            CompactToggle(isOn: $hapticsEnabled) {
                Label("触感反馈", systemImage: "hand.tap")
            }

            CompactToggle(isOn: $quickPromptsEnabled) {
                Label("快捷提问", systemImage: "text.bubble")
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
    }

    /// 当前 App 实际使用的界面语言（系统按 App 语言设置选出的本地化）
    private var currentLanguage: String {
        let id = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return Locale(identifier: "zh-Hans").localizedString(forIdentifier: id) ?? id
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
