import SwiftUI
import VeraBotCore

struct BotListView: View {
    @Environment(AppState.self) private var app
    @State private var bots: [Bot] = []
    @State private var limit = 20   // 服务端下发的软上限（Soft limit）
    @State private var editing: Bot?
    @State private var showCreate = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(bots) { bot in
                        NavigationLink(value: bot) { BotRow(bot: bot) }
                            .contextMenu {
                                Button { editing = bot } label: { Label("编辑与权限", systemImage: "slider.horizontal.3") }
                            }
                    }
                    .onDelete { idx in
                        let targets = idx.map { bots[$0] }
                        Task { await delete(targets) }
                    }
                } footer: {
                    Text("已创建 \(bots.count) 个 Bot · 每个 Bot 的对话与记忆相互隔离"
                         + (bots.count >= limit ? "（已达上限 \(limit) 个）" : ""))
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
            .overlay {
                if bots.isEmpty && errorText == nil {
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
                        // iOS 26 原生样式：只放首字母，由系统 Liquid Glass 圆形按钮承载（不再自绘背景）
                        Text(String((app.username ?? "?").prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundStyle(Color.brand)
                    }
                    .accessibilityLabel("设置")
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

    private func load() async {
        do {
            let r = try await app.api.bots()
            bots = r.bots
            limit = r.limit
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
            BotAvatar(emoji: bot.avatar, color: bot.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(bot.name).font(.headline)
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
