import SwiftUI
import VeraBotCore
import VeraBotData
import VeraBotNetworking

struct FeedView: View {
    @Environment(AppState.self) private var app
    @State private var model: FeedViewModel?
    private var identity: String { "\(app.userID.map(String.init) ?? "signed-out")|\(app.baseURLString)|\(app.sessionGeneration)" }
    var body: some View {
        NavigationStack {
            if let model, model.identity == identity { FeedScreen(api: app.groupAPI, vm: model) }
            else { ProgressView("正在加载发现…") }
        }
        .id(identity)
        .task(id: identity) {
            if let model { model.configure(api: app.groupAPI, identity: identity) }
            else { model = FeedViewModel(api: app.groupAPI, identity: identity) }
        }
    }
}

private enum FeedSheet: String, Identifiable {
    case plan, sources
    var id: String { rawValue }
}

private struct FeedScreen: View {
    let api: APIClient
    let vm: FeedViewModel
    @State private var bots: [Bot] = []
    @State private var botError: String?
    @State private var sheet: FeedSheet?
    @State private var detail: FeedItem?
    @State private var chat: FeedChatRoute?
    @State private var handoffTask: Task<Void, Never>?
    @State private var discussingItemID: Int?
    @State private var discussionError: String?
    var body: some View {
        List {
            Section { filters }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            if let setupError = vm.setupError { FeedErrorRow(message: setupError) { Task { await vm.loadSetup() } } }
            if let error = vm.error { FeedErrorRow(message: error) { Task { await vm.load() } } }
            if let botError { FeedErrorRow(message: botError) { Task { await loadBots() } } }
            if let notice = vm.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            if vm.setupLoaded && !vm.plan.enabled && !vm.query.savedOnly {
                Section {
                    Text(vm.plan.version == 0 ? "让 Bot 帮你关注感兴趣的内容" : "关注计划已暂停")
                        .font(.headline)
                    Text("选择 Bot、主题和订阅后启用。每日最多 \(vm.plan.dailyLimit) 条；收藏始终保留。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(vm.plan.version == 0 ? "设置关注计划" : "编辑并恢复计划") { sheet = .plan }
                }
            }
            if vm.items.isEmpty {
                Section {
                    if vm.loading { HStack { Spacer(); ProgressView(); Spacer() } }
                    else {
                        ContentUnavailableView(vm.query.savedOnly ? "暂无收藏" : "暂无内容", systemImage: vm.query.savedOnly ? "bookmark" : "newspaper", description: Text(vm.query.savedOnly ? "收藏的原文引用会保存在这里。" : "可调整筛选、检查来源，或等待后台采集后刷新。"))
                    }
                }
            } else {
                Section {
                    ForEach(vm.items) { item in
                        FeedCard(item: item, bots: bots, busy: vm.busy,
                                 preparing: discussingItemID == item.id && vm.busy,
                                 open: { detail = item }, discuss: { bot in discuss(item: item, bot: bot) })
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button("不感兴趣", role: .destructive) { Task { await vm.setState(id: item.id, state: FeedItemState(dismissed: true)) } }
                            Button(item.saved ? "取消收藏" : "收藏") { Task { await vm.setState(id: item.id, state: FeedItemState(saved: !item.saved)) } }.tint(.orange)
                        }
                        .disabled(vm.busy)
                    }
                    if vm.nextCursor != nil {
                        Button { Task { await vm.loadMore() } } label: {
                            HStack { Spacer(); if vm.loading { ProgressView() } else { Text("加载更多") }; Spacer() }
                        }.disabled(vm.loading)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $detail) { item in
            FeedDetailView(initialItem: item, vm: vm, bots: bots)
                .toolbar(.visible, for: .navigationBar)
        }
        .navigationDestination(item: $chat) { route in
            FeedDiscussionView(route: route)
                .toolbar(.visible, for: .navigationBar)
        }
        .alert("无法准备讨论", isPresented: Binding(get: { discussionError != nil }, set: { if !$0 { discussionError = nil } })) {
            Button("知道了", role: .cancel) { discussionError = nil }
        } message: { Text(discussionError ?? "") }
        .sheet(item: $sheet) { value in
            NavigationStack {
                switch value {
                case .plan: FeedPlanEditor(vm: vm, bots: bots)
                case .sources: FeedSourcesView(vm: vm, bots: bots)
                }
            }
        }
        .task {
            async let feedLoad: Void = vm.load()
            await loadBots()
            await feedLoad
        }
        .refreshable { await vm.refresh() }
        .onDisappear { handoffTask?.cancel(); handoffTask = nil }
    }
    private var filters: some View {
        VStack(spacing: 8) {
            Picker("内容类型", selection: Binding(get: { vm.query.kind ?? "" }, set: { kind in
                var query = vm.query; query.kind = kind.isEmpty ? nil : kind
                Task { await vm.apply(query: query) }
            })) {
                Text("全部").tag("")
                ForEach(FeedContentKind.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            HStack {
                Picker("供稿 Bot", selection: Binding(get: { vm.query.botID ?? 0 }, set: { id in
                    var query = vm.query; query.botID = id == 0 ? nil : id
                    Task { await vm.apply(query: query) }
                })) {
                    Text("全部 Bot").tag(0)
                    ForEach(bots) { Text($0.name).tag($0.id) }
                }
                Spacer()
                Toggle("仅收藏", isOn: Binding(get: { vm.query.savedOnly }, set: { saved in
                    var query = vm.query; query.savedOnly = saved
                    Task { await vm.apply(query: query) }
                })).fixedSize()
                managementMenu
            }.font(.subheadline)
        }.padding(.vertical, 4)
    }
    private var managementMenu: some View {
        Menu {
            Button("关注计划", systemImage: "slider.horizontal.3") { sheet = .plan }
            Button("订阅来源", systemImage: "dot.radiowaves.left.and.right") { sheet = .sources }
            Button("刷新", systemImage: "arrow.clockwise") { Task { await vm.refresh() } }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 36, minHeight: 36)
        }.accessibilityLabel("发现管理")
    }
    private func discuss(item: FeedItem, bot: Bot) {
        handoffTask?.cancel()
        discussingItemID = item.id
        handoffTask = Task {
            let context = await vm.context(id: item.id, botID: bot.id, allowedBotIDs: Set(bots.map(\.id)))
            guard !Task.isCancelled else { return }
            if let context { chat = FeedChatRoute(bot: bot, draft: context.prompt) }
            else { discussionError = vm.error ?? "无法准备讨论，请稍后重试。" }
        }
    }
    private func loadBots() async {
        do {
            let response = try await api.bots()
            guard !Task.isCancelled else { return }
            bots = response.bots; botError = nil
        } catch { if !Task.isCancelled { botError = "无法加载 Bot：\(error.localizedDescription)" } }
    }
}

struct FeedErrorRow: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.footnote).foregroundStyle(.red)
            Button("重试", action: retry).font(.footnote)
        }.accessibilityElement(children: .contain)
    }
}
