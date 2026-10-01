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
        ThemedForm {
            AccountSettingsSection()   // 账号置顶
            UsageSettingsSection()     // 用量（push 用量看板）
            MemorySettingsSection()    // 记忆：「Vera 了解的你」+ 允许 Bot 记住（Features/Memory）
            GeneralSettingsSection()   // 外观 / 通知 / 触感反馈 / 语言
            VoiceSettingsSection()     // 语音播放 + 语音引擎
            AboutSettingsSection()
            SignOutSettingsSection()   // 退出登录固定在最底部
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 开发 / 调试信息（服务器地址、健康检查、构建信息）统一放在调试页，不出现在普通设置里
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    DebugView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Image(systemName: "ladybug")
                }
                .accessibilityLabel("调试")
            }
        }
    }
}

/// 用量：单独一行，push 现有用量看板（QuotaView）。
/// 右侧用系统 LabeledContent 的次要文字显示「已用 N%」（今日 Token / 今日额度，来自 GET /api/quota）；
/// 加载中、失败或无有效额度时不显示数字。每次回到设置页重新拉取。
struct UsageSettingsSection: View {
    @Environment(AppState.self) private var app
    @State private var usedText: String?

    var body: some View {
        Section {
            NavigationLink {
                QuotaView()
                    .toolbar(.hidden, for: .tabBar)
            } label: {
                LabeledContent {
                    if let usedText { Text(usedText) }
                } label: {
                    Label("用量", systemImage: "chart.bar")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        // 失败时保留上一次的值（首次失败则为 nil → 不显示），不展示假数字
        if let q = try? await app.api.quota() { usedText = q.usedPercentText }
    }
}

/// 语音：语音播放开关 + 语音引擎
struct VoiceSettingsSection: View {
    @AppStorage(SettingsKeys.ttsEnabled) private var ttsEnabled = true
    @AppStorage(SettingsKeys.ttsEngine) private var engineRaw = TTSEngineKind.local.rawValue
    @Environment(SpeechPlayer.self) private var player

    var body: some View {
        Section {
            CompactToggle(isOn: $ttsEnabled) {
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

/// 关于：应用简介与版本号（构建号等详细信息见调试页）
struct AboutSettingsSection: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        Section("关于") {
            LabeledContent("版本", value: version)
            LabeledContent("应用", value: "VeraBot · 你的私人 AI 助理团队")
        }
    }
}
