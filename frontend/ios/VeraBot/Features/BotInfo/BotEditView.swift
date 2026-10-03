import PhotosUI
import SwiftUI
import VeraBotCore

/// Bot 详情 / Bot 设置：Bot 列表长按「编辑与权限」或对话页标题（infoMode）中使用。
/// 顶部卡片：点头像换照片 / 恢复默认形象，点昵称、标签弹出系统输入框修改。
/// 所有改动（含照片上传、删除）只在点「保存」时提交，「取消」/「关闭」全部丢弃。
struct BotEditView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let bot: Bot
    let onSaved: @MainActor (Bot) -> Void
    /// Bot 详情模式（对话页标题弹出的 sheet）：底部显示「清空对话」
    var infoMode = false
    var clearDisabled = false
    /// 清空对话；参数 includeMemories = true 时同时删除该 Bot 的记忆与对话摘要
    var onClear: (@MainActor (_ includeMemories: Bool) async -> Void)? = nil

    @State private var confirmClear = false
    private enum Field: Hashable { case persona, instructions }
    @FocusState private var focus: Field?
    @State private var draft: BotProfileDraft
    @State private var avatar = ""
    @State private var color = ""
    @State private var persona = ""
    @State private var instructions = ""
    @State private var tools: [ToolInfo] = []
    @State private var mcpServers: [MCPServer] = []
    @State private var mcpTools: [MCPTool] = []
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
    // 顶部卡片的系统弹窗
    @State private var showAvatarOptions = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?   // 未保存的新照片，只用于卡片预览
    @State private var showNameAlert = false
    @State private var nameInput = ""
    @State private var showTagsAlert = false
    @State private var tagsInput = ""
    @State private var inputError: String?
    /// 记忆列表按「已保存的」授权过滤（未保存的 Picker 改动不影响列表）
    private var botForMemoryList: Bot { freshBot ?? bot }
    private var savedBot: Bot { freshBot ?? bot }

    private var canDelegate: Bool { allowedTools.contains("ask_bot") }

    init(bot: Bot, onSaved: @escaping @MainActor (Bot) -> Void, infoMode: Bool = false, clearDisabled: Bool = false,
         onClear: (@MainActor (_ includeMemories: Bool) async -> Void)? = nil) {
        self.bot = bot
        self.onSaved = onSaved
        self.infoMode = infoMode
        self.clearDisabled = clearDisabled
        self.onClear = onClear
        _draft = State(initialValue: BotProfileDraft(bot: bot))
    }

    var body: some View {
        ThemedForm {
            Section {
                VStack(spacing: 8) {
                    Button { endEditing(); showAvatarOptions = true } label: { cardAvatar }
                        .buttonStyle(.plain)
                        .accessibilityLabel("更换头像")
                    Button { nameInput = draft.name; showNameAlert = true } label: {
                        Text(draft.name).font(.title2.bold())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("修改昵称")
                    Button { tagsInput = draft.tagsText; showTagsAlert = true } label: {
                        Text(draft.tags.isEmpty ? "添加标签" : draft.tagsText)
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("修改标签")
                    Text(persona.isEmpty ? "暂无人设简介" : persona)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineLimit(3)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(BotLook.emojis, id: \.self) { e in
                            Text(e).font(.title3).frame(width: 32, height: 32)
                                .background(avatar == e ? Color.brandSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { avatar = e }
                        }
                    }
                }
                HStack {
                    ForEach(BotLook.colors, id: \.self) { c in
                        Circle().fill(Color(hex: c)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.primary, lineWidth: BotLook.sameColor(color, c) ? 2 : 0))
                            .onTapGesture { color = c }
                    }
                }
            } header: {
                Text("默认形象")
            } footer: {
                Text("设置了相册照片时，优先显示照片。")
            }

            Section {
                // 多行：回车换行（不使用 submitLabel .next）；下拉表单 / 保存 / 关闭收起键盘
                TextField("例如：资深研究员，擅长资料检索与总结", text: $persona, axis: .vertical).lineLimit(3...8)
                    .focused($focus, equals: .persona)
            } header: {
                Text("人设")
            } footer: {
                Text("对其他 Bot 公开，协作时用来介绍自己。")
            }

            Section {
                TextField("例如：先给结论，再给要点，不超过 200 字", text: $instructions, axis: .vertical).lineLimit(3...8)
                    .focused($focus, equals: .instructions)
            } header: {
                Text("自定义指令")
            } footer: {
                Text("仅本 Bot 使用，不对其他 Bot 公开。")
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
                        Text("\(draft.name) 记住的内容")
                    }
                }
            } header: {
                Text("记忆")
            } footer: {
                Text("「本 Bot + 共享资料」还会读取「关于你」里所有 Bot 共享的资料。被其他 Bot 委派时，不会读取或写入你的记忆。")
            }

            Section {
                ForEach(tools.filter { !$0.isMCP }) { t in
                    CompactToggle(isOn: binding(for: t.name)) {
                        Text(t.displayName)
                    }
                }
            } header: {
                Text("工具权限")
            } footer: {
                Text("未勾选的工具不会提供给模型，且服务端会拒绝越权调用并记录审计日志。")
            }

            Section {
                if mcpServers.isEmpty {
                    Text("暂无 MCP 服务").foregroundStyle(.secondary)
                }
                ForEach(mcpServers) { server in
                    let rows = mcpTools.filter { $0.serverId == server.id }
                    Text(server.name).font(.subheadline)
                    if server.status != "connected" {
                        Text(server.status == "disabled" ? "已停用，可在设置中开启" : "需先在设置中连接")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if rows.isEmpty {
                        Text("还没有工具").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button("开启全部只读") {
                            allowedTools = Set(MCPToolRules.addingReadOnly(current: Array(allowedTools), tools: rows))
                        }
                        ForEach(rows) { tool in
                            CompactToggle(isOn: binding(for: tool.fullName)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.label)
                                    Text(tool.riskText).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(tool.status != "active")
                        }
                    }
                }
            } header: {
                Text("MCP 服务")
            } footer: {
                Text("按服务分组，默认关闭。每个 Bot 最多 \(MCPToolRules.maxPerBot) 个。「开启全部只读」只写入当前这些只读工具的名字。")
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
                Text("委派")
            } footer: {
                Text(delegationFooter)
            }

            Section("协作记录") {
                NavigationLink {
                    DelegationLogView(bot: bot)
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("查看协作记录", systemImage: "list.bullet.rectangle")
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
        // 两个入口都是 sheet：禁止下滑关闭，只能点「关闭」/「取消」或「保存」退出（未保存改动不会被误丢）
        .interactiveDismissDisabled()
        .onDisappear { endEditing() }   // push 协作记录 / 关闭 sheet 时收起键盘
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                DismissToolbarButton(kind: infoMode ? .close : .cancel) { endEditing(); dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { endEditing(); Task { await save() } }
                    .disabled(saving || !loaded)
            }
        }
        .confirmationDialog("头像", isPresented: $showAvatarOptions, titleVisibility: .hidden) {
            Button("从相册选择") { showPhotoPicker = true }
            if draft.canUseDefaultLook {
                Button("使用默认形象") { draft.useDefaultLook(); pendingImage = nil }
            }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .alert("修改昵称", isPresented: $showNameAlert) {
            TextField("昵称", text: $nameInput)
            Button("取消", role: .cancel) {}
            Button("确定") { inputError = draft.rename(nameInput) }
                .disabled(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("修改标签", isPresented: $showTagsAlert) {
            TextField("如：搜索, 查询, 调研", text: $tagsInput)
            Button("取消", role: .cancel) {}
            Button("确定") { inputError = draft.setTags(tagsInput) }
        } message: {
            Text("最多 \(BotTagRules.maxCount) 个，每个最多 \(BotTagRules.maxLength) 个字，用逗号或空格分隔。")
        }
        .alert("无法修改", isPresented: Binding(get: { inputError != nil }, set: { if !$0 { inputError = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(inputError ?? "")
        }
        .task { await load() }
    }

    /// 卡片头像：未保存的新照片 > 待删除（显示默认形象）> 已保存的照片 / 默认形象；表情与底色实时预览。
    @ViewBuilder private var cardAvatar: some View {
        let emoji = avatar.isEmpty ? bot.avatar : avatar
        let tint = color.isEmpty ? bot.color : color
        if let pendingImage {
            BotAvatar(emoji: emoji, color: tint, image: pendingImage, size: 72)
        } else if draft.photo == .remove {
            BotAvatar(emoji: emoji, color: tint, size: 72)
        } else {
            LiveBotAvatar(botID: bot.id, emoji: emoji, color: tint,
                          hasAvatar: savedBot.hasAvatar, updatedAt: savedBot.avatarUpdatedAt, size: 72)
        }
    }

    /// 读取相册照片并裁成正方形 JPEG；只放进待保存状态，不上传。
    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = AvatarImage.jpegData(from: image),
              let display = UIImage(data: jpeg) else {
            errorText = "无法读取这张照片"
            return
        }
        draft.choosePhoto(jpeg)
        pendingImage = display
        errorText = nil
    }

    /// 结束编辑：清除 FocusState 并释放第一响应者（收起键盘）
    private func endEditing() {
        focus = nil
        Keyboard.dismiss()
    }

    private var delegationFooter: String {
        var s = canDelegate ? "只能委派给勾选的 Bot（且对方需开启「接受委派」）。" : "先在上方开启「委派其他 Bot」工具。"
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
        avatar = bot.avatar; color = bot.color; persona = bot.persona; instructions = bot.instructions
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
                if !draft.isDirty { draft = BotProfileDraft(bot: fresh) }   // 以服务端最新数据为基线
                freshBot = fresh
            }
            loaded = true
        } catch {
            errorText = app.message(for: error)
        }
        do {
            let response = try await app.api.mcpServers()
            mcpServers = response.servers
            var rows: [MCPTool] = []
            for server in response.servers {
                rows.append(contentsOf: try await app.api.mcpTools(serverID: server.id).tools)
            }
            mcpTools = rows
        } catch {
            if errorText == nil { errorText = app.message(for: error) }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let patch = BotPatch(name: draft.name, avatar: avatar, color: color,
                             persona: persona, instructions: instructions,
                             allowedTools: allowedTools.sorted(),
                             delegateTo: canDelegate ? delegateTo.sorted() : [],
                             acceptDelegation: acceptDelegation,
                             memoryAccess: memoryAccess,
                             tags: draft.tags)
        let updated: Bot
        do {
            updated = try await app.api.updateBot(bot.id, patch)
        } catch {
            errorText = app.message(for: error)
            return
        }
        // 资料先保存，再提交照片改动；照片失败时资料已生效，留在本页可重试
        do {
            var final = updated
            switch draft.photo {
            case .unchanged:
                break
            case .replace(let jpeg):
                final = try await app.api.uploadBotAvatar(botID: bot.id, jpeg: jpeg)
                app.avatars.setBot(id: bot.id, image: pendingImage ?? UIImage(data: jpeg), updatedAt: final.avatarUpdatedAt)
            case .remove:
                final = try await app.api.deleteBotAvatar(botID: bot.id)
                app.avatars.setBot(id: bot.id, image: nil, updatedAt: nil)
            }
            onSaved(final)
            endEditing()   // 关闭前确保键盘已收起（第一响应者已释放）
            dismiss()
        } catch {
            onSaved(updated)
            errorText = "其他修改已保存，头像未更新：\(app.message(for: error))"
        }
    }
}
