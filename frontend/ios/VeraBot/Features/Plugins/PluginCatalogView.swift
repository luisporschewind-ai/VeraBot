import SwiftUI
import VeraBotCore

/// 精选目录。安装成功后进入详情，并提示需要同意。
struct PluginCatalogView: View {
    @Environment(AppState.self) private var app
    @State private var items: [Plugin] = []
    @State private var errorText: String?
    @State private var busyID: String?
    @State private var openedID: String?

    private var categories: [String] {
        var seen: [String] = []
        for item in items where !seen.contains(item.category) {
            seen.append(item.category.isEmpty ? "其他" : item.category)
        }
        return seen
    }

    var body: some View {
        ThemedForm {
            ForEach(categories, id: \.self) { category in
                Section(category) {
                    ForEach(items.filter { ($0.category.isEmpty ? "其他" : $0.category) == category }) { item in
                        catalogRow(item)
                    }
                }
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle("浏览插件")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedID) { id in
            PluginDetailView(pluginID: id, promptConsent: true)
                .toolbar(.hidden, for: .tabBar)
        }
        .task { await reload() }
    }

    private func catalogRow(_ item: Plugin) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.publisher).font(.caption).foregroundStyle(.secondary)
                Text(item.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !item.available {
                    Text("服务地址未配置").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if item.installed {
                Text("已安装").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button("安装") { Task { await install(item) } }
                    .buttonStyle(.bordered)
                    .disabled(!item.available || busyID != nil)
            }
        }
        .opacity(item.available ? 1 : 0.45)
    }

    private func reload() async {
        do {
            items = try await app.api.pluginCatalog().catalog
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func install(_ item: Plugin) async {
        busyID = item.pluginId
        defer { busyID = nil }
        do {
            _ = try await app.api.installPlugin(id: item.pluginId)
            await reload()
            openedID = item.pluginId
        } catch {
            errorText = app.message(for: error)
        }
    }
}
