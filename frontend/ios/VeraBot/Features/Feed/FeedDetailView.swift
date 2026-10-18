import SwiftUI
import VeraBotCore
import VeraBotData

struct FeedChatRoute: Hashable, Identifiable {
    let bot: Bot
    let draft: String
    var id: Int { bot.id }
}

struct FeedDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let initialItem: FeedItem
    let vm: FeedViewModel
    let bots: [Bot]
    @State private var choosingBot = false
    @State private var chat: FeedChatRoute?
    private var item: FeedItem { vm.details[initialItem.id] ?? vm.items.first(where: { $0.id == initialItem.id }) ?? initialItem }
    var body: some View {
        List {
            Section {
                Text(item.title).font(.title2.bold()).textSelection(.enabled)
                LabeledContent("来源", value: item.sourceName)
                if let author = item.author, !author.isEmpty { LabeledContent("作者", value: author) }
                if let date = item.publishedAt { LabeledContent("发布时间", value: formatted(date)) }
                if let duration = item.durationSeconds { LabeledContent("时长", value: "\(duration / 60) 分 \(duration % 60) 秒") }
                if let url = safeOriginalURL {
                    Link(item.kind == "audio" || item.kind == "video" ? "在原站打开 / 播放" : "阅读原文", destination: url)
                }
                Text("内容和媒体来自外部来源。音视频播放在原站进行。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(item.evidenceLabel) {
                Text(item.summary.isEmpty ? "该订阅未提供可引用的文本，请阅读原文。" : item.summary).textSelection(.enabled)
                Text("仅展示订阅实际提供的文本；不代表已读取原站全文或完成音视频转写。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("推荐依据") {
                if !item.recommendationReason.isEmpty { Text(item.recommendationReason) }
                ForEach(item.recommendedBy, id: \.botID) { rec in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.botName).font(.subheadline.bold())
                        Text(rec.reason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if let error = vm.error { FeedErrorRow(message: error) { Task { await vm.loadDetail(id: item.id) } } }
            Section {
                Button(item.saved ? "取消收藏" : "收藏引用", systemImage: item.saved ? "bookmark.fill" : "bookmark") {
                    Task { await vm.setState(id: item.id, state: FeedItemState(saved: !item.saved)) }
                }
                Button(item.read ? "标为未读" : "标为已读", systemImage: item.read ? "envelope.badge" : "envelope.open") {
                    Task { await vm.setState(id: item.id, state: FeedItemState(read: !item.read)) }
                }
                Button("问 Bot", systemImage: "bubble.left.and.text.bubble.right") { choosingBot = true }
                    .disabled(bots.isEmpty)
                if bots.isEmpty { Text("加载有效 Bot 后即可准备提问草稿。").font(.caption).foregroundStyle(.secondary) }
                Button("不感兴趣", role: .destructive) {
                    Task { if await vm.setState(id: item.id, state: FeedItemState(dismissed: true)) != nil { dismiss() } }
                }
            }.disabled(vm.busy)
        }
        .navigationTitle("内容详情")
        .navigationBarTitleDisplayMode(.inline)
        .inAppBrowser()
        .task { await vm.loadDetail(id: initialItem.id) }
        .sheet(isPresented: $choosingBot) {
            NavigationStack {
                FeedAskBotSheet(itemID: item.id, vm: vm, bots: bots, presented: $choosingBot) { bot, context in
                    chat = FeedChatRoute(bot: bot, draft: context.prompt)
                }
            }
        }
        .navigationDestination(item: $chat) { route in
            FeedDiscussionView(route: route)
        }
    }
    private var safeOriginalURL: URL? {
        guard let url = URL(string: item.url), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
    private func formatted(_ value: String) -> String {
        guard let date = VeraBotDate.parse(value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct FeedAskBotSheet: View {
    @Environment(\.dismiss) private var dismiss
    let itemID: Int
    let vm: FeedViewModel
    let bots: [Bot]
    @Binding var presented: Bool
    let ready: (Bot, FeedContext) -> Void
    @State private var selected: Int?
    @State private var handoffTask: Task<Void, Never>?
    var body: some View {
        Form {
            Section {
                Text("选择 Bot 后生成含来源和依据的提问草稿。已有未发送草稿会保留在前面，由你确认后发送。")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(bots) { bot in
                    Button { selected = bot.id } label: {
                        HStack { Text(bot.name); Spacer(); if selected == bot.id { Image(systemName: "checkmark") } }
                    }
                }
            }
            if let error = vm.error { Text(error).foregroundStyle(.red).font(.footnote) }
            Button(vm.busy ? "正在准备…" : "打开提问草稿") {
                handoffTask?.cancel()
                handoffTask = Task {
                    guard let bot = bots.first(where: { $0.id == selected }),
                          let context = await vm.context(id: itemID, botID: bot.id, allowedBotIDs: Set(bots.map(\.id))), !Task.isCancelled, presented else { return }
                    ready(bot, context); dismiss()
                }
            }.disabled(selected == nil || vm.busy)
        }
        .navigationTitle("问 Bot")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { presented = false; cancelHandoff(); dismiss() } } }
        .onAppear { vm.clearError() }
        .onChange(of: presented) { _, visible in if !visible { cancelHandoff() } }
        .onDisappear { cancelHandoff() }
    }
    private func cancelHandoff() {
        handoffTask?.cancel(); handoffTask = nil
    }
}


struct FeedDiscussionView: View {
    @Environment(AppState.self) private var app
    let route: FeedChatRoute
    var body: some View {
        ChatView(bot: route.bot, api: app.api, repository: app.conversationRepository,
                 initialDraft: route.draft, hostingTab: 5)
    }
}
