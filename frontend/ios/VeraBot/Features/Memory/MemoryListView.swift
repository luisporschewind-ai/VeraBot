import SwiftUI
import VeraBotCore

/// 「Vera 了解的你」：查看 / 编辑 / 删除 / 手动添加 / 清空记忆。
/// botFilter 不为 nil 时（Bot 详情进入）只显示该 Bot 能看到的记忆，清空只清该 Bot 的「本 Bot 记忆」。
struct MemoryListView: View {
    var botFilter: Bot? = nil

    @Environment(AppState.self) private var app
    @AppStorage(SettingsKeys.memoryIntroShown) private var introShown = false
    @State private var memories: [Memory] = []
    @State private var bots: [Bot] = []
    @State private var loaded = false
    @State private var errorText: String?
    @State private var editing: MemoryEditView.Mode?
    @State private var confirmClear = false
    @State private var showIntro = false
    @State private var busy: Set<Int> = []

    private var pending: [Memory] { memories.filter { $0.status.isPending } }
    private var global: [Memory] { memories.filter { $0.status == .active && $0.scope == .global } }
    private struct BotGroup: Identifiable {
        let id: Int
        let bot: Bot?
        let items: [Memory]
    }

    private var perBot: [BotGroup] {
        let scoped = memories.filter { $0.status == .active && $0.scope != .global && $0.botId != nil }
        let ids = Array(Set(scoped.compactMap(\.botId))).sorted()
        return ids.map { id in BotGroup(id: id, bot: bots.first { $0.id == id }, items: scoped.filter { $0.botId == id }) }
    }

    var body: some View {
        ThemedList {
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
            if !pending.isEmpty {
                Section("待确认") {
                    ForEach(pending) { m in
                        VStack(alignment: .leading, spacing: 6) {
                            row(m)
                            HStack(spacing: 8) {
                                Button(m.action == .delete ? "忘掉" : "记住") { Task { await confirm(m) } }
                                    .prominentButtonStyle()
                                Button("不用") { Task { await reject(m) } }
                                    .glassButtonStyle()
                                if busy.contains(m.id) { ProgressView() }
                            }
                            .controlSize(.small)
                            .disabled(busy.contains(m.id))
                        }
                    }
                }
            }
            if !global.isEmpty {
                Section {
                    ForEach(global) { m in editableRow(m) }
                } header: {
                    Text("关于你 · 所有 Bot 可用")
                } footer: {
                    if botFilter?.memoryAccess == .bot {
                        Text("「\(botFilter?.name ?? "")」当前只使用自己的记忆，不读取这些共享资料。")
                    }
                }
            }
            ForEach(perBot) { group in
                Section {
                    ForEach(group.items) { m in
                        if m.scope == .summary || m.type == .summary {
                            row(m)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { Task { await delete(m) } } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        } else {
                            editableRow(m)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        if let b = group.bot {
                            LiveBotAvatar(botID: b.id, emoji: b.avatar, color: b.color,
                                          hasAvatar: b.hasAvatar, updatedAt: b.avatarUpdatedAt, size: 22)
                        }
                        Text("仅 \(group.bot?.name ?? group.items.first?.botName ?? "Bot")")
                    }
                }
            }
        }
        .overlay {
            if loaded && memories.isEmpty && errorText == nil {
                ContentUnavailableView {
                    Label("还没有记住任何内容", systemImage: "brain")
                } description: {
                    Text("在对话中说「记住…」，或点右上角 ＋ 添加")
                }
            }
        }
        .navigationTitle(botFilter.map { "\($0.name) 记住的内容" } ?? "Vera 了解的你")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = .create(defaultBot: botFilter) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加记忆")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label(botFilter == nil ? "清空全部记忆" : "清空 \(botFilter?.name ?? "") 的记忆", systemImage: "trash")
                    }
                    .disabled(memories.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多")
            }
        }
        .confirmationDialog(botFilter == nil ? "清空全部记忆？" : "清空「\(botFilter?.name ?? "")」的记忆？",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button(botFilter == nil ? "清空全部记忆" : "清空", role: .destructive) { Task { await clear() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(botFilter == nil ? "所有 Bot 都会忘记这些内容，此操作不能撤销。"
                 : "只删除仅「\(botFilter?.name ?? "")」可用的记忆，共享资料保留。此操作不能撤销。")
        }
        .alert("关于记忆", isPresented: $showIntro) {
            Button("知道了", role: .cancel) { introShown = true }
        } message: {
            Text("Bot 只会在你确认后记住信息，相关的记忆会随对话一起发送给模型服务（DeepSeek）用来个性化回答。健康、财务信息加密保存；密码、验证码、证件号、卡号永远不会被记住。")
        }
        .sheet(item: $editing) { mode in
            MemoryEditView(mode: mode, bots: bots) { await load() }
                .environment(app)
        }
        .refreshable { await load() }
        .task {
            await load()
            if !introShown { showIntro = true }
        }
    }

    private func row(_ m: Memory) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if m.action == .delete {
                Text("忘掉：\(m.targetContent ?? "")").lineLimit(3)
            } else {
                Text(m.content).lineLimit(3)
                if m.action == .update, let old = m.targetContent {
                    Text("原来：\(old)").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                if m.sensitive { Image(systemName: "lock").accessibilityLabel("敏感，加密保存") }
                Text(m.detailLine())
            }
            .font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func editableRow(_ m: Memory) -> some View {
        Button { editing = .edit(m) } label: { row(m).foregroundStyle(.primary) }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { Task { await delete(m) } } label: { Label("删除", systemImage: "trash") }
                Button { editing = .edit(m) } label: { Label("编辑", systemImage: "pencil") }
            }
    }

    private func load() async {
        do {
            async let ms = app.api.memories(MemoryQuery(statuses: [.proposed, .candidate, .active], visibleTo: botFilter?.id))
            async let bs = app.api.bots()
            let (mr, br) = try await (ms, bs)
            memories = mr.memories
            bots = br.bots
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
        loaded = true
    }

    private func confirm(_ m: Memory) async {
        busy.insert(m.id); defer { busy.remove(m.id) }
        do { _ = try await app.api.confirmMemory(id: m.id, content: nil) } catch { errorText = app.message(for: error) }
        await load()
    }

    private func reject(_ m: Memory) async {
        busy.insert(m.id); defer { busy.remove(m.id) }
        do { _ = try await app.api.rejectMemory(id: m.id) } catch { errorText = app.message(for: error) }
        await load()
    }

    private func delete(_ m: Memory) async {
        memories.removeAll { $0.id == m.id }   // 与系统邮件一致：左滑删除不再二次确认
        do { _ = try await app.api.deleteMemory(id: m.id) } catch { errorText = app.message(for: error) }
        await load()
    }

    private func clear() async {
        do {
            if let b = botFilter {
                _ = try await app.api.clearMemories(scope: .bot, botID: b.id)
            } else {
                _ = try await app.api.clearMemories(scope: nil, botID: nil)
            }
        } catch {
            errorText = app.message(for: error)
        }
        await load()
    }
}
