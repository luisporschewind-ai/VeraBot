import SwiftUI
import VeraBotCore

struct BotListView: View {
    @Environment(AppState.self) private var app
    @State private var bots: [Bot] = []
    @State private var limit = 20   // 服务端下发的软上限（Soft limit）
    @State private var editing: Bot?
    @State private var pendingDelete: Bot?   // 左滑「删除」只弹确认框，确认后才调用 API
    @State private var showCreate = false
    @State private var errorText: String?
    @State private var query = ""
    @State private var searchActive = false     // 点击右上角放大镜后才挂载搜索栏；未激活时页面上不存在搜索框
    @State private var searchPresented = false  // 系统搜索栏的焦点 / 展开状态；取消后收起并清空关键词
    @State private var pinning: Set<Int> = []    // 正在与服务端同步置顶状态的 Bot，避免连点重复提交
    @State private var linkedChat: LinkedChat?
    @State private var linkedPlugin: String?

    var body: some View {
        NavigationStack {
            // 沉浸式平铺列表：白底、无圆角分组、无分隔线（plainListRow 见 Theme）
            List {
                ForEach(filteredBots) { bot in
                    NavigationLink(value: bot) { BotRow(bot: bot) }
                        .contextMenu {
                            pinButton(for: bot)
                            Button { editing = bot } label: { Label("编辑与权限", systemImage: "slider.horizontal.3") }
                        }
                        .swipeActions(edge: .leading) { pinButton(for: bot) }
                        // 不用 .onDelete / role: .destructive：它们会先把行动画移除，这里只弹确认框
                        .swipeActions(edge: .trailing) {
                            Button { pendingDelete = bot } label: { Label("删除", systemImage: "trash") }
                                .tint(.red)
                        }
                        .plainListRow()
                        .listRowBackground(bot.isPinned ? Color.sectionFill : Color.appBackground)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                        .plainListRow()
                }
            }
            .listStyle(.plain)
            .confirmationDialog(pendingDelete.map { BotDeletion.title($0.name) } ?? "",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingDelete) { bot in
                Button("删除", role: .destructive) { Task { await delete(bot) } }
                Button("取消", role: .cancel) {}
            } message: { bot in
                Text(BotDeletion.message(bot.name))
            }
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
            .navigationDestination(item: $linkedChat) { route in
                ChatView(bot: route.bot, api: app.api, highlightMessageID: route.messageID)
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: Binding(
                get: { linkedPlugin != nil },
                set: { if !$0 { linkedPlugin = nil } }
            )) {
                if let linkedPlugin {
                    PluginDetailView(pluginID: linkedPlugin)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            .onChange(of: app.pendingLink) { _, link in
                open(link)
            }
            .toolbar {
                // iOS 26：系统会给工具栏项套一层 Liquid Glass 共享底（按内容算出的胶囊），
                // 包在头像外面看起来不是圆的。关掉这层底，只显示与右侧圆形按钮等大的正圆头像。
                if #available(iOS 26.0, *) {
                    // 隐藏共享玻璃底后，头像仍按玻璃按钮的内边距排版，左边距（30pt）比右侧＋按钮的右边距（≈16pt）大；
                    // 左移 14pt 让左右两侧到屏幕边缘的距离一致。
                    ToolbarItem(placement: .topBarLeading) { settingsLink(avatarSize: 44).offset(x: -14) }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { settingsLink(avatarSize: 30) }
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

    /// 首页左上角：正圆头像（照片或首字圆底），点按进入设置。
    private func settingsLink(avatarSize: CGFloat) -> some View {
        NavigationLink {
            SettingsView()
                .toolbar(.hidden, for: .tabBar)
        } label: {
            HomeAvatarLabel(name: app.displayName, image: app.avatars.userImage, size: avatarSize)
        }
        .accessibilityLabel("设置")
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
            bots = BotOrdering.sorted(r.bots)
            limit = r.limit
            for bot in r.bots {
                app.avatars.reconcileBot(id: bot.id, hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt)
            }
            errorText = nil
            open(app.pendingLink)
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func open(_ link: DeepLink?) {
        guard let link else { return }
        switch link {
        case .chat(let botID, let messageID):
            guard let bot = bots.first(where: { $0.id == botID }) else { return }
            linkedChat = LinkedChat(bot: bot, messageID: messageID)
            app.pendingLink = nil
        case .plugin(let id):
            linkedPlugin = id
            app.pendingLink = nil
        default:
            break
        }
    }

    private func delete(_ bot: Bot) async {
        do {
            _ = try await app.api.deleteBot(bot.id)
            await load()
        } catch {
            await load()
            errorText = app.message(for: error)
        }
    }

    @ViewBuilder
    private func pinButton(for bot: Bot) -> some View {
        Button { togglePin(bot) } label: {
            Label(bot.isPinned ? "取消置顶" : "置顶", systemImage: bot.isPinned ? "pin.slash.fill" : "pin.fill")
        }
        .tint(bot.isPinned ? Color.unpinTint : Color.pinTint)
    }

    /// 置顶 / 取消置顶：乐观更新——本地先用原生 List 动画把行移到新位置，再同步服务端。
    /// 旧实现先 await PATCH 再重排：点按后要等一次网络往返才动，且重排与左滑按钮收起动画撞在一起，
    /// 行会短暂空白再跳到新位置。现在等滑动按钮收起（约 0.25s）后立即 withAnimation 移动，
    /// 服务端返回后只校正 pinnedAt（顺序不变则无可见变化）；失败时动画回滚并提示错误。
    private func togglePin(_ bot: Bot) {
        guard !pinning.contains(bot.id) else { return }
        pinning.insert(bot.id)
        let wantPinned = !bot.isPinned
        let before = bots
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))   // 让左滑操作按钮先收起，避免与行移动动画冲突
            withAnimation(.snappy) { bots = BotOrdering.togglingPin(bots, id: bot.id) }
            defer { pinning.remove(bot.id) }
            do {
                let updated = try await app.api.updateBot(bot.id, BotPatch(pinned: wantPinned))
                let reconciled = BotOrdering.replacingPinnedAt(bots, id: bot.id, value: updated.pinnedAt)
                if reconciled.map(\.id) == bots.map(\.id) {
                    bots = reconciled
                } else {
                    withAnimation(.snappy) { bots = reconciled }
                }
                errorText = nil
            } catch {
                withAnimation(.snappy) {
                    bots = BotOrdering.replacingPinnedAt(bots, id: bot.id,
                                                         value: before.first { $0.id == bot.id }?.pinnedAt)
                }
                errorText = app.message(for: error)
            }
        }
    }

}

private struct LinkedChat: Identifiable, Hashable {
    let bot: Bot
    let messageID: Int?
    var id: Int { bot.id }
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
                    if bot.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.pinTint)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("已置顶")
                    }
                    BotTagChip(tags: bot.tags)   // 一个浅灰圆角矩形，「搜索, 查询, 调研」，放不下尾部截断
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
