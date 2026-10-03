import SwiftUI
import VeraBotCore

/// 设置 → 插件。一行进入插件页，右侧是已安装的外部插件数量。
struct PluginsSettingsSection: View {
    @Environment(AppState.self) private var app
    @State private var installedCount: Int?

    var body: some View {
        Section {
            NavigationLink {
                PluginListView()
                    .toolbar(.hidden, for: .tabBar)
            } label: {
                LabeledContent {
                    if let installedCount { Text("已安装 \(installedCount) 个") }
                } label: {
                    Label("插件", systemImage: "puzzlepiece.extension")
                }
            }
        } footer: {
            Text("插件为 Bot 提供外部能力。每个插件需要单独同意后才会调用。")
        }
        .task { await reload() }
    }

    private func reload() async {
        guard let plugins = try? await app.api.plugins().plugins else { return }
        installedCount = plugins.filter { $0.kind == "mcp" && $0.installed }.count
    }
}
