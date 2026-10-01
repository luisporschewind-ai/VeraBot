import SwiftUI
import VeraBotCore
import VeraBotTTS

// MARK: - 设置（Settings）
//
// 扩展方式（Extensible）：
//   1. 在 VeraBotKit/VeraBotCore 的 SettingsKeys 中新增持久化 key（统一 "vb_" 前缀，存 UserDefaults / @AppStorage）；
//   2. 新建一个 `struct XxxSettingsSection: View`（返回一个 Section），加入 SettingsView.body 的 Form 即可。
// 每个 Section 自包含自己的状态与文案，互不影响。

struct SettingsView: View {
    var body: some View {
        Form {
            AccountSettingsSection()   // 账号置顶
            VoiceSettingsSection()     // 语音播放 + 语音引擎
            AboutSettingsSection()
            SignOutSettingsSection()   // 退出登录固定在最底部
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 语音：语音播放开关 + 语音引擎
struct VoiceSettingsSection: View {
    @AppStorage(SettingsKeys.ttsEnabled) private var ttsEnabled = true
    @AppStorage(SettingsKeys.ttsEngine) private var engineRaw = TTSEngineKind.local.rawValue
    @Environment(SpeechPlayer.self) private var player

    var body: some View {
        Section {
            Toggle(isOn: $ttsEnabled) {
                Label("语音播放", systemImage: "speaker.wave.2")
            }
            .onChange(of: ttsEnabled) { if !ttsEnabled { player.stop() } }
            Picker(selection: $engineRaw) {
                ForEach(TTSEngineKind.allCases) { kind in
                    Text(kind.title).tag(kind.rawValue)
                        .selectionDisabled(!kind.isAvailable)
                }
            } label: {
                Label("语音引擎", systemImage: "waveform")
            }
            .disabled(!ttsEnabled)
        } header: {
            Text("语音")
        } footer: {
            Text("开启后，在用户消息和 Bot 回复气泡下方显示 🔊 朗读按钮。云端 TTS 即将支持。")
        }
    }
}

/// 退出登录：单独一组，固定在设置页最底部
struct SignOutSettingsSection: View {
    @Environment(AppState.self) private var app
    @Environment(SpeechPlayer.self) private var player
    @State private var confirmLogout = false

    var body: some View {
        Section {
            Button("退出登录", role: .destructive) { confirmLogout = true }
                .confirmationDialog("确定退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
                    Button("退出登录", role: .destructive) {
                        player.stop()
                        app.signOut()
                    }
                    Button("取消", role: .cancel) {}
                }
        }
    }
}

/// 关于：版本信息
struct AboutSettingsSection: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "-"
        let b = info?["CFBundleVersion"] as? String ?? "-"
        return "\(v) (\(b))"
    }

    var body: some View {
        Section("关于") {
            LabeledContent("版本", value: version)
            LabeledContent("应用", value: "VeraBot · 你的私人 AI 助理团队")
        }
    }
}
