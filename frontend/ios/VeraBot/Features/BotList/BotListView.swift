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
    @State private var searchActive = false     // 点击右上角放大镜后才挂载搜索栏；未激活时页面上不存在搜索框
    @State private var searchPresented = false  // 系统搜索栏的焦点 / 展开状态；取消后收起并清空关键词

    var body: some View {
        NavigationStack {
            // 沉浸式平铺列表：白底、无圆角分组、无分隔线（plainListRow 见 Theme）
            List {
                ForEach(filteredBots) { bot in
                    NavigationLink(value: bot) { BotRow(bot: bot) }
                        .contextMenu {
                            Button { editing = bot } label: { Label("编辑与权限", systemImage: "slider.horizontal.3") }
                        }
                        .plainListRow()
                }
                .onDelete { idx in
                    let targets = idx.map { filteredBots[$0] }
                    Task { await delete(targets) }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                        .plainListRow()
                }
            }
            .listStyle(.plain)
            .themedPageBackground()
            .overlay {
                if !trimmedQuery.isEmpty && filteredBots.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                } else if bots.isEmpty && errorText == nil {
                    ContentUnavailableView {
                        Label("还没有 Bot", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("点击右上角「＋」或下方按钮创建第一个助理")
                    } actions: {
                        Button("＋ 创建第一个 Bot") { showCreate = true }.prominentButtonStyle()
                    }
                }
            }
            // 首页不显示导航标题；inline 保留紧凑导航栏，避免大标题占位。
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onDemandSearchable(active: searchActive, text: $query, isPresented: $searchPresented,
                                prompt: "搜索 Bot 或消息")
            .onChange(of: searchPresented) { wasPresented, presented in
                // 取消 / 收起搜索：卸载搜索栏并清空关键词，下拉也不会再露出搜索框
                if wasPresented && !presented { endSearch() }
            }
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
                    Button { beginSearch() } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("搜索")
                }
                // iOS 26：固定间隔把搜索与＋拆成两个独立的 Liquid Glass 圆形按钮（不合并成一个胶囊）
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
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

    private func beginSearch() {
        guard !searchActive else { searchPresented = true; return }
        searchActive = true
        // 先挂载搜索栏，下一帧再展开并聚焦，确保系统搜索栏能拿到焦点
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            searchPresented = true
        }
    }

    private func endSearch() {
        searchPresented = false
        searchActive = false
        query = ""
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

private extension View {
    /// 按需搜索：仅在 active 时挂载 .searchable（始终展开的导航栏抽屉），未激活时不挂载，避免常驻 / 下拉露出搜索框
    @ViewBuilder
    func onDemandSearchable(active: Bool, text: Binding<String>, isPresented: Binding<Bool>,
                            prompt: LocalizedStringKey) -> some View {
        if active {
            searchable(text: text, isPresented: isPresented,
                       placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        } else {
            self
        }
    }
}

struct BotRow: View {
    let bot: Bot

    var body: some View {
        HStack(spacing: 12) {
            LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                           hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(bot.name).font(.headline).lineLimit(1).layoutPriority(1)
                    BotTagChips(tags: bot.tags)
                    Spacer(minLength: 8)
                    if let date = ListTimestamp.rowDate(for: bot) {
                        Text(ListTimestamp.label(for: date))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                }
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var preview: String {
        let raw = bot.lastMessage?.content ?? (bot.persona.isEmpty ? "点击开始私聊" : bot.persona)
        return raw.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\n", with: " ")
    }
}
