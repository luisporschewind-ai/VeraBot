import SwiftUI
import VeraBotCore

/// Bot 编辑与权限（Edit & Permissions）：Bot 列表长按「编辑与权限」或 Bot 详情（infoMode）中使用。
struct BotEditView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let bot: Bot
    let onSaved: @MainActor (Bot) -> Void
    /// Bot 详情模式（对话页标题弹出的 sheet）：顶部显示头像/名称/人设卡片，底部显示「清空对话」
    var infoMode = false
    var clearDisabled = false
    /// 清空对话；参数 includeMemories = true 时同时删除该 Bot 的记忆与对话摘要
    var onClear: (@MainActor (_ includeMemories: Bool) async -> Void)? = nil

    @State private var confirmClear = false
    private enum Field: Hashable { case name, persona, instructions }
    @FocusState private var focus: Field?
    @State private var name = ""
    @State private var avatar = ""
    @State private var persona = ""
    @State private var instructions = ""
    @State private var tools: [ToolInfo] = []
    @State private var guardrails: Guardrails?
    @State private var others: [Bot] = []
    @State private var allowedTools: Set<String> = []
    @State private var delegateTo: Set<Int> = []
    @State private var acceptDelegation = false
    @State private var memoryAccess: MemoryAccess = .botAndGlobal
    @State private var memoryCount: Int?
    @State private var saving = false
    @State private var errorText: String?
    @State private var loaded = false
    @State private var freshBot: Bot?
    /// 记忆列表按「已保存的」授权过滤（未保存的 Picker 改动不影响列表）
    private var botForMemoryList: Bot { freshBot ?? bot }

    private let emojis = ["🤖", "🦊", "🐼", "🐱", "🦉", "🐧", "🦄", "🐙", "🌟", "🧠", "📚", "🔬", "💼", "🎨", "🍀", "☕"]
    private var canDelegate: Bool { allowedTools.contains("ask_bot") }

    var body: some View {
        ThemedForm {
            if infoMode {
                Section {
                    VStack(spacing: 8) {
                        LiveBotAvatar(botID: bot.id, emoji: avatar.isEmpty ? bot.avatar : avatar, color: bot.color,
                                      hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt, size: 72)
                        Text(name.isEmpty ? bot.name : name).font(.title2.bold())
                        Text(persona.isEmpty ? "暂无人设简介" : persona)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            Section("基本信息") {
                HStack(spacing: 12) {
                    BotAvatar(emoji: avatar, color: bot.color, size: 44)
                    TextField("昵称", text: $name)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .persona }
                }
                BotAvatarPhotoControls(botID: bot.id)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).font(.title3).frame(width: 32, height: 32)
                                .background(avatar == e ? Color.brandSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { avatar = e }
                        }
                    }
                }
                // 多行：回车换行（不使用 submitLabel .next）；下拉表单 / 保存 / 关闭收起键盘
                TextField("人设 Persona（对其他 Bot 公开）", text: $persona, axis: .vertical).lineLimit(3...8)
                    .focused($focus, equals: .persona)
                TextField("自定义指令 Instructions（私有）", text: $instructions, axis: .vertical).lineLimit(3...8)
                    .focused($focus, equals: .instructions)
            }

            Section {
                Picker(selection: $memoryAccess) {
                    ForEach(MemoryAccess.allCases) { a in Text(a.title).tag(a) }
                } label: {
                    Label("记忆", systemImage: "brain")
                }
                NavigationLink {
                    MemoryListView(botFilter: botForMemoryList)
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    LabeledContent {
                        if let memoryCount { Text("\(memoryCount)") }
                    } label: {
                        Text("\(name.isEmpty ? bot.name : name) 记住的内容")
                    }
                }
            } header: {
                Text("记忆")
            } footer: {
                Text("「本 Bot + 共享资料」还会读取「关于你」里所有 Bot 共享的资料。被其他 Bot 委派时，不会读取或写入你的记忆。")
            }

            Section {
                ForEach(tools) { t in
                    CompactToggle(isOn: binding(for: t.name)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.label ?? t.name)
                            Text(t.name).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("工具权限 Tool allowlist")
            } footer: {
                Text("未勾选的工具不会提供给模型，且服务端会拒绝越权调用并记录审计日志。")
            }

            Section {
                if others.isEmpty {
                    Text("暂无其他 Bot").foregroundStyle(.secondary)
                }
                ForEach(others) { o in
                    CompactToggle(isOn: targetBinding(o.id)) {
                        HStack {
                            LiveBotAvatar(botID: o.id, emoji: o.avatar, color: o.color,
                                           hasAvatar: o.hasAvatar, updatedAt: o.avatarUpdatedAt, size: 26)
                            Text(o.name)
                            if !o.acceptDelegation {
                                Text("未开放委派").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    .disabled(!canDelegate)
                }
                CompactToggle("接受其他 Bot 的委派", isOn: $acceptDelegation)
            } header: {
                Text("委派 Delegation")
            } footer: {
                Text(delegationFooter)
            }

            Section("审计 Trace") {
                NavigationLink {
                    DelegationLogView(bot: bot)
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("协作记录", systemImage: "list.bullet.rectangle")
                }
            }

            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }

            if let onClear {
                Section {
                    Button(role: .destructive) { endEditing(); confirmClear = true } label: {
                        Label("清空对话", systemImage: "trash").foregroundStyle(.red)
                    }
                    .disabled(clearDisabled)
                    .confirmationDialog("清空与「\(bot.name)」的全部对话？", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("仅清空对话", role: .destructive) {
                            Task { await onClear(false); endEditing(); dismiss() }   // 清空后关闭 sheet，回到对话页
                        }
                        Button("清空对话和「\(bot.name)」的记忆", role: .destructive) {
                            Task { await onClear(true); endEditing(); dismiss() }
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("对话内容将被删除，此操作不可撤销。默认保留记忆（可在「Vera 了解的你」中管理）；选择第二项会同时删除仅「\(bot.name)」可用的记忆，所有 Bot 共享的资料不受影响。")
                    }
                } footer: {
                    Text("清空后该 Bot 将忘记此前的全部对话内容；记住的信息默认保留。")
                }
            }
        }
        .navigationTitle(infoMode ? "Bot 详情" : "Bot 设置")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        // 键盘工具栏「完成」只用于非 sheet 场景：sheet（Bot 详情）里的 .keyboard 工具栏（inputAccessoryView）
        // 关闭后会让对话页的键盘避让少算工具栏高度（输入栏被键盘遮住）；sheet 内用下拉 / 保存 / 关闭收起键盘
        .keyboardDoneButton(enabled: !infoMode) { focus = nil }
        .onDisappear { endEditing() }   // push 协作记录 / 关闭 sheet（含下滑关闭）时收起键盘
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                DismissToolbarButton(kind: infoMode ? .close : .cancel) { endEditing(); dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { endEditing(); Task { await save() } }
                    .disabled(saving || !loaded || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task { await load() }
    }

    /// 结束编辑：清除 FocusState 并释放第一响应者（收起键盘）
    private func endEditing() {
        focus = nil
        Keyboard.dismiss()
    }

    private var delegationFooter: String {
        var s = canDelegate ? "只能委派给勾选的 Bot（且对方需开启「接受委派」）。" : "先在上方开启「委派其他 Bot（ask_bot）」工具。"
        if let g = guardrails {
            s += "护栏：最多 \(g.maxDelegationDepth) 跳、每轮最多 \(g.maxDelegationsPerTurn) 次委派、共享背景最多 \(g.maxSharedContext) 字；对方看不到你们的聊天记录。"
        }
        return s
    }

    private func binding(for tool: String) -> Binding<Bool> {
        Binding(get: { allowedTools.contains(tool) },
                set: { on in if on { allowedTools.insert(tool) } else { allowedTools.remove(tool) } })
    }

    private func targetBinding(_ id: Int) -> Binding<Bool> {
        Binding(get: { delegateTo.contains(id) },
                set: { on in if on { delegateTo.insert(id) } else { delegateTo.remove(id) } })
    }

    private func load() async {
        name = bot.name; avatar = bot.avatar; persona = bot.persona; instructions = bot.instructions
        allowedTools = Set(bot.allowedTools); delegateTo = Set(bot.delegateTo); acceptDelegation = bot.acceptDelegation
        memoryAccess = bot.memoryAccess; memoryCount = bot.memoryCount
        do {
            async let t = app.api.tools()
            async let b = app.api.bots()
            let (tr, br) = try await (t, b)
            tools = tr.tools
            guardrails = tr.guardrails
            others = br.bots.filter { $0.id != bot.id }
            if let fresh = br.bots.first(where: { $0.id == bot.id }) {
                allowedTools = Set(fresh.allowedTools); delegateTo = Set(fresh.delegateTo); acceptDelegation = fresh.acceptDelegation
                memoryAccess = fresh.memoryAccess; memoryCount = fresh.memoryCount
                freshBot = fresh
            }
            loaded = true
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let patch = BotPatch(name: name.trimmingCharacters(in: .whitespaces), avatar: avatar, color: nil,
                             persona: persona, instructions: instructions,
                             allowedTools: allowedTools.sorted(),
                             delegateTo: canDelegate ? delegateTo.sorted() : [],
                             acceptDelegation: acceptDelegation,
                             memoryAccess: memoryAccess)
        do {
            let updated = try await app.api.updateBot(bot.id, patch)
            onSaved(updated)
            endEditing()   // 关闭前确保键盘已收起（第一响应者已释放）
            dismiss()
        } catch {
            errorText = app.message(for: error)
        }
    }
}
