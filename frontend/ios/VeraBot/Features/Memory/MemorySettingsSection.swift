import SwiftUI
import VeraBotCore

/// 设置 › 记忆：「Vera 了解的你」入口 + 「允许 Bot 记住」总开关。
/// 开关状态以服务器为准（影响服务端召回与记忆工具），不是 @AppStorage；保存失败时回退并提示。
struct MemorySettingsSection: View {
    @Environment(AppState.self) private var app
    @State private var enabled = true
    @State private var count: Int?
    @State private var syncing = false
    @State private var notice: PageNotice?

    var body: some View {
        Section {
            NavigationLink {
                MemoryListView()
                    .toolbar(.hidden, for: .tabBar)
            } label: {
                LabeledContent {
                    if let count { Text("\(count) 条") }
                } label: {
                    Label("Vera 了解的你", systemImage: "brain.head.profile")
                }
            }
            CompactToggle(isOn: Binding(get: { enabled }, set: { on in Task { await set(on) } })) {
                Label("允许 Bot 记住", systemImage: "brain")
            }
            .disabled(syncing)
            if let notice {
                PageConnectionNotice(notice: notice) { Task { await load() } }
            }
        } header: {
            Text("记忆")
        } footer: {
            Text("Bot 只会在你确认后记住信息。健康、财务信息加密保存；密码、验证码、证件号、卡号不会被记住。清空对话会删除对话摘要，已确认的记忆默认保留。")
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let s = try await app.api.memorySettings()
            enabled = s.enabled
            count = s.activeCount
            notice = nil
        } catch {
            notice = .fromLoad(error, message: app.message(for: error))
        }
    }

    private func set(_ on: Bool) async {
        let previous = enabled
        enabled = on
        syncing = true
        defer { syncing = false }
        do {
            let s = try await app.api.updateMemorySettings(enabled: on)
            enabled = s.enabled
            count = s.activeCount
            notice = nil
        } catch {
            enabled = previous   // 失败回退
            let message = app.message(for: error)
            notice = UserFacingError.isTransport(error) ? .fromAction(error, message: message) : .sentence("保存失败：\(message)")
        }
    }
}
