import SwiftUI
import VeraBotCore

struct BotListView: View {
    @Environment(AppState.self) private var app
    @State private var bots: [Bot] = []
    @State private var limit = 20   // 服务端下发的软上限（Soft limit）
    @State private var editing: Bot?
    @State private var showCreate = false
    @State private var errorText: String?
    @State private var query = ""
    @State private var searching = false   // 由右上角放大镜按钮打开系统搜索栏

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredBots) { bot in
                        NavigationLink(value: bot) { BotRow(bot: bot) }
                            .contextMenu {
                                Button { editing = bot } label: { Label("编辑与权限", systemImage: "slider.horizontal.3") }
                            }
                    }
                    .onDelete { idx in
                        let targets = idx.map { filteredBots[$0] }
                        Task { await delete(targets) }
                    }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
            .overlay {
                if !trimmedQuery.isEmpty && filteredBots.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                } else if bots.isEmpty && errorText == nil {
                    ContentUnavailableView {
                        Label("还没有 Bot", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("点击右上角「＋」或下方按钮创建第一个助理")
                    } actions: {
                        Button("＋ 创建第一个 Bot") { showCreate = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("我的 Bot")
            .searchable(text: $query, isPresented: $searching,
                        placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索 Bot 或消息")
            .navigationDestination(for: Bot.self) { bot in
                ChatView(bot: bot, api: app.api)
                    .toolbar(.hidden, for: .tabBar)   // 二级页面隐藏底部 Tab 栏，返回根页面时自动恢复
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        // 无照片时只放首字，由系统圆形按钮承载；有照片时在按钮里显示圆形头像
                        HomeAvatarLabel(name: app.displayName, image: app.avatars.userImage)
                    }
                    .accessibilityLabel("设置")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { searching = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("搜索")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }   // 原生圆形玻璃按钮
                        .disabled(bots.count >= limit)
                        .accessibilityLabel("创建 Bot")
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateBotSheet { Task { await load() } }
                    .toolbar(.hidden, for: .tabBar)
                    .presentationDetents([.large])
            }
            .sheet(item: $editing, onDismiss: { Task { await load() } }) { bot in
                NavigationStack { BotEditView(bot: bot) { _ in }.toolbar(.hidden, for: .tabBar) }
            }
            .onAppear { Task { await load() } }   // 从对话页返回时刷新（对话页可能新建了 Bot）
            .refreshable { await load() }
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 按 Bot 名称与最后一条消息预览过滤（系统本地化不区分大小写匹配）
    private var filteredBots: [Bot] {
        let q = trimmedQuery
        guard !q.isEmpty else { return bots }
        return bots.filter { bot in
            bot.name.localizedStandardContains(q)
                || (bot.lastMessage?.content.localizedStandardContains(q) ?? false)
        }
    }

    private func load() async {
        do {
            let r = try await app.api.bots()
            bots = r.bots
            limit = r.limit
            for bot in r.bots {
                app.avatars.reconcileBot(id: bot.id, hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt)
            }
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func delete(_ targets: [Bot]) async {
        for b in targets {
            _ = try? await app.api.deleteBot(b.id)
        }
        await load()
    }
}

struct BotRow: View {
    let bot: Bot

    var body: some View {
        HStack(spacing: 12) {
            LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                           hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bot.name).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = ListTimestamp.rowDate(for: bot) {
                        Text(ListTimestamp.label(for: date))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var preview: String {
        let raw = bot.lastMessage?.content ?? (bot.persona.isEmpty ? "点击开始私聊" : bot.persona)
        return raw.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\n", with: " ")
    }
}
