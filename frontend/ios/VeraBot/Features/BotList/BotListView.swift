import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct BotListView: View {
    @Environment(AppState.self) private var app
    @State private var bots: [Bot] = []
    @State private var limit = 20   // 服务端下发的软上限（Soft limit）
    @State private var editing: Bot?
    @State private var pendingDelete: Bot?   // 左滑「删除」只弹确认框，确认后才调用 API
    @State private var showCreate = false
    @State private var showSettings = false   // 点头像：设置页以大尺寸原生 sheet 弹出
    @State private var showSearch = false
    @State private var errorText: String?
    @State private var loading = false
    @State private var loaded = false
    @State private var connectionIssue: ConnectionIssue?
    @State private var reloadRequested = false
    @State private var pinning: Set<Int> = []    // 正在与服务端同步置顶状态的 Bot，避免连点重复提交
    @State private var linkedChat: LinkedChat?
    @State private var linkedPlugin: String?

    var body: some View {
        NavigationStack {
            // 沉浸式平铺列表：白底、无圆角分组、无分隔线（plainListRow 见 Theme）
            List {
                if !bots.isEmpty, let connectionIssue {
                    BotConnectionView(issue: connectionIssue, retrying: loading, compact: true) {
                        Task { await load() }
                    }
                    .plainListRow()
                }
                ForEach(bots) { bot in
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
                if bots.isEmpty, let connectionIssue {
                    BotConnectionView(issue: connectionIssue, retrying: loading) { Task { await load() } }
                } else if bots.isEmpty && (!loaded || loading) {
                    BotLoadingView()
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
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
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
            .sheet(isPresented: $showSearch) {
                BotSearchSheet(bots: bots)
                    .environment(app)
                    .toolbar(.hidden, for: .tabBar)
                    .presentationDetents([.large])
            }
            .sheet(item: $editing, onDismiss: { Task { await load() } }) { bot in
                NavigationStack { BotEditView(bot: bot) { _ in }.toolbar(.hidden, for: .tabBar) }
            }
            .sheet(isPresented: $showSettings) {
                // 设置内部仍要 push 二级页（用量、插件、调试等），sheet 内自带 NavigationStack
                NavigationStack { SettingsView() }
                    .environment(app)
                    .presentationDetents([.large])
            }
            // 在设置页退出登录：根视图换成登录页之前先关闭 sheet，避免残留设置页。
            .onChange(of: app.token) { _, token in
                if token == nil { showSettings = false }
            }
            .task { await load() }   // 返回时刷新；离开视图时取消请求
            .refreshable { await load() }
        }
    }

    /// 首页左上角：正圆头像（照片或首字圆底），点按弹出设置页。
    private func settingsLink(avatarSize: CGFloat) -> some View {
        Button { showSettings = true } label: {
            HomeAvatarLabel(name: app.displayName, image: app.avatars.userImage, size: avatarSize)
        }
        .accessibilityLabel("设置")
    }

    private func load() async {
        guard !loading else { reloadRequested = true; return }
        loading = true
        let generation = app.sessionGeneration
        let endpoint = app.baseURLString
        defer {
            loading = false
            if reloadRequested {
                reloadRequested = false
                if !Task.isCancelled { Task { await load() } }
            }
        }
        do {
            let r = try await app.api.bots()
            guard !Task.isCancelled, app.isCurrentSession(generation), app.baseURLString == endpoint else { return }
            bots = BotOrdering.sorted(r.bots)
            limit = r.limit
            for bot in r.bots {
                app.avatars.reconcileBot(id: bot.id, hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt)
            }
            errorText = nil
            connectionIssue = nil
            app.connectionDiagnostic = nil
            loaded = true
            open(app.pendingLink)
        } catch {
            guard !Task.isCancelled, app.isCurrentSession(generation), app.baseURLString == endpoint,
                  (error as? URLError)?.code != .cancelled else { return }
            loaded = true
            connectionIssue = ConnectionIssue.classify(error)
            if connectionIssue != nil {
                errorText = nil
                app.connectionDiagnostic = error.localizedDescription
            } else {
                errorText = app.message(for: error)
            }
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

private struct BotSearchSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let bots: [Bot]

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var results: [Bot] {
        guard !trimmedQuery.isEmpty else { return bots }
        return bots.filter { bot in
            bot.name.localizedStandardContains(trimmedQuery)
                || (bot.lastMessage?.content.localizedStandardContains(trimmedQuery) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索 Bot 或消息", text: $query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .accessibilityLabel("搜索 Bot 或消息")
                    if !query.isEmpty {
                        Button {
                            query = ""
                            searchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                List {
                    if bots.isEmpty {
                        ContentUnavailableView("还没有 Bot", systemImage: "person.crop.circle")
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: trimmedQuery)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(results) { bot in
                            NavigationLink(value: bot) { BotRow(bot: bot) }
                                .plainListRow()
                                .listRowBackground(bot.isPinned ? Color.sectionFill : Color.appBackground)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
            }
            .themedPageBackground()
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DismissToolbarButton(kind: .close) { dismiss() }
                }
            }
            .navigationDestination(for: Bot.self) { bot in
                ChatView(bot: bot, api: app.api)
                    .toolbar(.hidden, for: .tabBar)
            }
            .task {
                await Task.yield()
                searchFocused = true
            }
        }
    }
}

private struct LinkedChat: Identifiable, Hashable {
    let bot: Bot
    let messageID: Int?
    var id: Int { bot.id }
}

struct BotRow: View {
    let bot: Bot

    var body: some View {
        HStack(spacing: 12) {
            LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                           hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt,
                           animated: true, appearance: bot.supportedAppearance)
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
