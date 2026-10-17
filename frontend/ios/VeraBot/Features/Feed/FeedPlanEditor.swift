import SwiftUI
import VeraBotCore
import VeraBotData

struct FeedPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    let vm: FeedViewModel
    let bots: [Bot]
    @State private var enabled: Bool
    @State private var selectedBots: Set<Int>
    @State private var topics: String
    @State private var exclusions: String
    @State private var useMemory: Bool
    @State private var suggestion: FeedSuggestion?
    @State private var version: Int

    init(vm: FeedViewModel, bots: [Bot]) {
        self.vm = vm; self.bots = bots
        _enabled = State(initialValue: vm.plan.enabled)
        _selectedBots = State(initialValue: Set(vm.plan.botIDs))
        _topics = State(initialValue: vm.plan.topics.joined(separator: "、"))
        _exclusions = State(initialValue: vm.plan.excludedTopics.joined(separator: "、"))
        _useMemory = State(initialValue: vm.plan.useMemory)
        _version = State(initialValue: vm.plan.version)
    }
    var body: some View {
        Form {
            Section {
                Toggle("启用关注计划", isOn: $enabled)
                Text("仅启用后开始后台采集，每日最多 \(vm.plan.dailyLimit) 条新内容；暂停后仍可查看收藏。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("1 · 选择供稿 Bot") {
                if bots.isEmpty { Text("暂无可用 Bot，请先在助理页面创建 Bot，或返回重试加载。").foregroundStyle(.secondary) }
                ForEach(bots) { bot in
                    Toggle(bot.name, isOn: Binding(get: { selectedBots.contains(bot.id) }, set: { value in
                        if value { selectedBots.insert(bot.id) } else { selectedBots.remove(bot.id) }
                    }))
                }
            }
            Section("2 · 主题与记忆") {
                TextField("关注主题，用顿号或逗号分隔", text: $topics, axis: .vertical)
                TextField("排除主题，用顿号或逗号分隔", text: $exclusions, axis: .vertical)
                Toggle("允许使用已授权记忆建议", isOn: $useMemory)
                Text("建议同时受账号和 Bot 的记忆权限约束；不会自动保存计划或订阅。")
                    .font(.caption).foregroundStyle(.secondary)
                if !vm.plan.useMemory && useMemory {
                    Text("已保存计划关闭了记忆使用，本次建议仍不使用记忆。保存开启后方可重新请求。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(vm.busy ? "正在处理…" : "获取主题与来源建议") {
                    Task { suggestion = await vm.suggest(botIDs: validSelectedBots, topics: split(topics), useMemory: useMemory) }
                }.disabled(vm.busy || validSelectedBots.isEmpty)
                if let suggestion {
                    Text(suggestion.basis).font(.footnote).foregroundStyle(.secondary)
                    if !suggestion.topics.isEmpty {
                        Text("建议主题：" + suggestion.topics.joined(separator: "、"))
                        Button("采用建议主题") { topics = suggestion.topics.joined(separator: "、") }
                    }
                }
            }
            Section("3 · 选择订阅来源") {
                Text("已添加 \(vm.sources.count) 个来源。来源订阅先独立保存，启用计划后才会采集。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(suggestedSources) { source in
                    FeedCatalogRow(source: source, vm: vm, bots: bots.filter { selectedBots.contains($0.id) })
                }
                NavigationLink("管理来源 / 添加自定义订阅") { FeedSourcesView(vm: vm, bots: bots) }
            }
            if let setupError = vm.setupError {
                FeedErrorRow(message: setupError) { Task { await vm.loadSetup(); version = vm.plan.version } }
            }
            if let error = vm.error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("重新读取服务器计划版本，保留输入") {
                        Task { await vm.loadSetup(); version = vm.plan.version }
                    }
                }
            }
            Section {
                Button(vm.busy ? "正在保存…" : "保存关注计划") {
                    Task {
                        let update = FeedPlanUpdate(enabled: enabled, botIDs: validSelectedBots, topics: split(topics), excludedTopics: split(exclusions), useMemory: useMemory, expectedVersion: version)
                        if await vm.savePlan(update) { dismiss() }
                    }
                }.disabled(vm.busy || !vm.setupLoaded || (enabled && (validSelectedBots.isEmpty || vm.sources.isEmpty)))
                if enabled && vm.sources.isEmpty { Text("启用前请先添加一个订阅来源。").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(vm.plan.version == 0 ? "设置关注计划" : "关注计划")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .interactiveDismissDisabled(vm.busy)
        .inAppBrowser()
        .onAppear { vm.clearError() }
    }
    private var suggestedSources: [FeedCatalogSource] {
        guard let suggestion, !suggestion.sources.isEmpty else { return vm.catalog }
        return suggestion.sources
    }
    private var validSelectedBots: [Int] { selectedBots.intersection(Set(bots.map(\.id))).sorted() }
    private func split(_ value: String) -> [String] {
        var seen = Set<String>()
        return value.components(separatedBy: CharacterSet(charactersIn: ",，、\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

struct FeedCatalogRow: View {
    let source: FeedCatalogSource
    let vm: FeedViewModel
    let bots: [Bot]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source.name).font(.headline)
            Text(FeedContentKind(rawValue: source.kind)?.label ?? source.kind).font(.caption).foregroundStyle(.secondary)
            if !source.description.isEmpty { Text("来源简介：" + source.description).font(.footnote).foregroundStyle(.secondary) }
            if !source.reason.isEmpty { Text(source.reason).font(.caption).foregroundStyle(.secondary) }
            Text(source.url).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            Menu {
                ForEach(bots) { bot in Button("由\(bot.name)供稿") { add(botID: bot.id) } }
                Button("仅关注此来源") { add(botID: nil) }
            } label: { Label("添加订阅", systemImage: "plus.circle") }
            .disabled(vm.busy)
            if vm.sources.contains(where: { $0.url == source.url }) {
                Text("已在来源列表中，可在那里检查 Bot 关联和暂停状态。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
    private func add(botID: Int?) {
        Task { _ = await vm.addSource(FeedSourceCreate(name: source.name, url: source.url, kind: source.kind, botID: botID)) }
    }
}
