import SwiftUI
import VeraBotCore
import VeraBotData

struct FeedSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    let vm: FeedViewModel
    let bots: [Bot]
    var body: some View {
        List {
            Section {
                NavigationLink { FeedAddSourceView(vm: vm, bots: bots) } label: { Label("添加自定义订阅", systemImage: "plus") }
                Text("支持公开 HTTPS RSS、Atom 和播客订阅。账号、付费平台及需要登录的内容尚未接入。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let setupError = vm.setupError { FeedErrorRow(message: setupError) { Task { await vm.loadSetup() } } }
            if let error = vm.error { FeedErrorRow(message: error) { Task { await vm.loadSetup() } } }
            Section("我的来源") {
                if vm.sources.isEmpty { Text("尚未添加订阅来源").foregroundStyle(.secondary) }
                ForEach(vm.sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(source.name).font(.headline)
                            Spacer()
                            Text(source.enabled ? "已启用" : "已暂停").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(FeedContentKind(rawValue: source.kind)?.label ?? source.kind).font(.caption).foregroundStyle(.secondary)
                        if let botID = source.botID {
                            Text("供稿 Bot：" + (bots.first(where: { $0.id == botID })?.name ?? "已不可用"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(source.url).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("最近成功：" + formatted(source.lastSuccessAt)).font(.caption)
                        Text("下次检查：" + formatted(source.nextFetchAt)).font(.caption).foregroundStyle(.secondary)
                        if let error = source.lastError, !error.isEmpty {
                            Text("采集失败 \(source.failureCount) 次：\(error)").font(.caption).foregroundStyle(.red)
                        }
                        Button(source.enabled ? "暂停 / 屏蔽来源" : "恢复来源") {
                            Task { await vm.setSource(id: source.id, enabled: !source.enabled) }
                        }.disabled(vm.busy)
                    }.padding(.vertical, 4)
                }
            }
            Section("来源目录") {
                ForEach(vm.catalog) { source in FeedCatalogRow(source: source, vm: vm, bots: bots) }
            }
            Section {
                Text("暂停来源后普通列表会隐藏相关内容，收藏引用仍保留。采集由后台运行，刷新不会立即产生新内容。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("订阅来源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .refreshable { await vm.loadSetup() }
    }
    private func formatted(_ text: String?) -> String {
        guard let text else { return "暂无" }
        guard let date = VeraBotDate.parse(text) else { return text }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct FeedAddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    let vm: FeedViewModel
    let bots: [Bot]
    @State private var name = ""
    @State private var url = ""
    @State private var kind = "news"
    @State private var botID = 0
    var body: some View {
        Form {
            Section("公开订阅") {
                TextField("来源名称", text: $name)
                TextField("https://… 订阅地址", text: $url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Picker("默认内容类型", selection: $kind) {
                    ForEach(FeedContentKind.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                Picker("供稿 Bot", selection: $botID) {
                    Text("仅关注来源").tag(0)
                    ForEach(bots) { Text($0.name).tag($0.id) }
                }
                Text("必须是无需登录的 HTTPS RSS / Atom 地址。实际媒体类型会按订阅内容识别。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = vm.error { Text(error).font(.footnote).foregroundStyle(.red) }
            Button(vm.busy ? "正在添加…" : "添加订阅") {
                Task {
                    let create = FeedSourceCreate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), url: url.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, botID: botID == 0 ? nil : botID)
                    if await vm.addSource(create) { dismiss() }
                }
            }.disabled(vm.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .navigationTitle("添加订阅")
        .onAppear { vm.clearError() }
    }
}
