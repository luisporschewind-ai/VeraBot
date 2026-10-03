import SwiftUI
import VeraBotCore

/// 插件页：内置、外部、浏览插件。同步中时轮询，最多 20 次。
struct PluginListView: View {
    @Environment(AppState.self) private var app
    @State private var plugins: [Plugin] = []
    @State private var errorText: String?

    private var builtins: [Plugin] { plugins.filter(\.isBuiltin) }
    private var external: [Plugin] { plugins.filter { $0.kind == "mcp" && $0.installed } }

    var body: some View {
        ThemedForm {
            Section {
                ForEach(builtins) { plugin in
                    NavigationLink {
                        BuiltinPluginDetailView(pluginID: plugin.pluginId)
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        pluginRow(plugin)
                    }
                }
            } header: {
                Text("内置")
            }

            Section {
                if external.isEmpty {
                    Text("还没有安装外部插件").foregroundStyle(.secondary)
                }
                ForEach(external) { plugin in
                    NavigationLink {
                        PluginDetailView(pluginID: plugin.pluginId)
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        pluginRow(plugin)
                    }
                }
            } header: {
                Text("外部")
            }

            Section {
                NavigationLink {
                    PluginCatalogView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("浏览插件", systemImage: "square.grid.2x2")
                }
            }

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle("插件")
        .navigationBarTitleDisplayMode(.inline)
        .task { await watch() }
    }

    private func pluginRow(_ plugin: Plugin) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                Text(plugin.stateTitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: plugin.icon)
        }
    }

    private func watch() async {
        for _ in 0..<20 {
            await reload()
            let waiting = external.contains { $0.enabled && ($0.state == "syncing" || $0.syncStatus == "pending" || $0.syncStatus == "syncing") }
            if !waiting { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
        }
    }

    private func reload() async {
        do {
            plugins = try await app.api.plugins().plugins
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }
}
