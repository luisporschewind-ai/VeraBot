import SwiftUI
import VeraBotCore
import VeraBotData
import VeraBotNetworking

struct GroupInfoView: View {
    @Bindable var model: GroupChatViewModel
    var onGroupUpdated: ((ChatGroup) -> Void)? = nil
    let onDeleted: () -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var contentTab = "settings"
    @State private var name = ""
    @State private var clearConfirm = false
    @State private var deleteConfirm = false
    @State private var saving = false
    @State private var error: String?
    @State private var showingAdd = false
    @State private var memberPendingRemove: ChatGroupMember?

    private var botCount: Int { BotProductLimits.botMemberCount(in: model.group.members) }
    private var canAddMember: Bool { BotProductLimits.canAddMember(currentBotCount: botCount) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        GroupMemberAvatarStack(
                            members: model.group.members.filter(\.available),
                            size: 72,
                            overlap: 22
                        )
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                        TextField("名称", text: $name)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 12, trailing: 20))
                }
                Section {
                    Picker("群内容", selection: $contentTab) {
                        Text("设置").tag("settings")
                        Text("文件").tag("file")
                        Text("图片").tag("image")
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                if contentTab == "settings" {
                    memberSection
                    if model.busy { Section { Button("先停止当前讨论") { Task { await model.stop() } }.disabled(model.confirmingStop) } }
                    Section {
                        Button("清空群历史", role: .destructive) { clearConfirm = true }
                        Button("删除群聊", role: .destructive) { deleteConfirm = true }
                    }.disabled(model.busy || saving)
                    if let error {
                        Section {
                            ConnectionNotice(title: error)
                        }
                    }
                } else {
                    Section {
                        LibraryView(scope: .group(id: model.group.id), initialKind: contentTab, embedded: true)
                            .id(contentTab)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                }
            }.navigationTitle("群设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissToolbarButton(kind: .close) { dismiss() }
                }
                if contentTab == "settings" {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await perform {
                        try await model.update(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                        onGroupUpdated?(model.group)
                        dismiss()
                    } } }.disabled(saving || model.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 64)
                }
                }
            }.onAppear { name = model.group.name }
            .confirmationDialog("清空本群历史？", isPresented: $clearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { Task { await perform { try await model.clear(); dismiss() } } }
            } message: { Text("仅删除本群聊天记录。") }
            .confirmationDialog("删除这个群聊？", isPresented: $deleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) { Task { await perform { try await model.delete(); dismiss(); onDeleted() } } }
            } message: { Text("群和全部群历史将一起删除。") }
            .alert(
                memberPendingRemove.map { "移除 \($0.name)？" } ?? "移除成员？",
                isPresented: Binding(
                    get: { memberPendingRemove != nil },
                    set: { if !$0 { memberPendingRemove = nil } }
                )
            ) {
                Button("取消", role: .cancel) { memberPendingRemove = nil }
                Button("移除", role: .destructive) {
                    guard let member = memberPendingRemove else { return }
                    memberPendingRemove = nil
                    Task { await confirmRemove(member) }
                }
            } message: {
                Text("该成员将离开此群聊。Bot 本身会保留。")
            }
            .sheet(isPresented: $showingAdd) {
                AddGroupMemberSheet(
                    memberBotIDs: Set(model.group.members.compactMap(\.botID)),
                    currentBotCount: botCount
                ) { botIDs in
                    showingAdd = false
                    Task { await confirmAdd(botIDs) }
                }
            }
        }
    }

    private var memberSection: some View {
        Section {
            ForEach(model.group.members) { member in
                GroupInfoMemberRow(member: member)
                    .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canRemove(member) {
                            // 不用 role: .destructive：系统会在确认前就把行滑走/隐藏；敏感操作用 .tint(.red)。
                            Button {
                                memberPendingRemove = member
                            } label: {
                                Label("移除", systemImage: "minus.circle.fill")
                            }
                            .tint(.red)
                            .accessibilityLabel("移除 \(member.name)")
                        }
                    }
            }
            Button {
                if canAddMember { showingAdd = true }
                else { error = BotProductLimits.groupSelectionFullMessage }
            } label: {
                Label("添加成员", systemImage: "person.badge.plus")
                    .foregroundStyle(canAddMember && !saving ? Color.blue : Color.secondary)
            }
            .disabled(saving)
            .accessibilityHint(canAddMember ? "选择要加入的 Bot" : BotProductLimits.groupSelectionFullMessage)
        } header: {
            Text("群成员（\(botCount)）")
        } footer: {
            Text("成员共享本群文字记录；群聊不会读取私聊或长期记忆。")
        }
    }

    private func canRemove(_ member: ChatGroupMember) -> Bool {
        // 不可用历史行不计入 Bot 下限；仍绑定 Bot 的成员受 min 2 限制。
        if member.botID == nil { return true }
        return BotProductLimits.canRemoveMember(currentBotCount: botCount)
    }

    private func confirmRemove(_ member: ChatGroupMember) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let updated = try await model.removeMember(memberID: member.id)
            withAnimation {
                model.applyGroup(updated)
            }
            onGroupUpdated?(model.group)
            error = nil
        } catch {
            // 失败时不改本地成员列表，行保持在原位。
            self.error = app.message(for: error)
        }
    }

    private func confirmAdd(_ botIDs: [Int]) async {
        guard !saving, !botIDs.isEmpty else { return }
        saving = true
        defer { saving = false }
        let result = await model.addMembers(botIDs: botIDs)
        if result.addedCount > 0 {
            withAnimation {
                model.applyGroup(result.group)
            }
            onGroupUpdated?(model.group)
        }
        if let failure = result.failure {
            self.error = app.message(for: failure)
        } else {
            error = nil
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !saving else { return }; saving = true; defer { saving = false }
        do {
            try await action()
            error = nil
        } catch {
            self.error = app.message(for: error)
        }
    }
}

private struct GroupInfoMemberRow: View {
    let member: ChatGroupMember

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            GroupMemberAvatar(member: member, size: 30).accessibilityHidden(true)
            Text(member.name).font(.body)
            Spacer(minLength: 0)
            if !member.available {
                Text("不可用").font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

/// 多选尚未入群的 Bot；风格对齐 CreateGroupSheet（无底部说明 footer）。
private struct AddGroupMemberSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let memberBotIDs: Set<Int>
    let currentBotCount: Int
    let onConfirm: ([Int]) -> Void
    @State private var bots: [Bot] = []
    @State private var selected: Set<Int> = []
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    private var candidates: [Bot] { bots.filter { !memberBotIDs.contains($0.id) } }
    private var projectedCount: Int { currentBotCount + selected.count }
    private var canSelectMore: Bool { BotProductLimits.canAddMember(currentBotCount: projectedCount) }
    private var canSubmit: Bool { !selected.isEmpty && !saving && !loading }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if loading { ProgressView() }
                    else if candidates.isEmpty {
                        Text(bots.isEmpty ? "还没有可加入的 Bot。" : "所有 Bot 都已在群中。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { bot in
                            let isSelected = selected.contains(bot.id)
                            Button {
                                toggle(bot.id, isSelected: isSelected)
                            } label: {
                                // 行高对齐 GroupInfoMemberRow：头像 30、间距 10、相同 listRowInsets。
                                HStack(alignment: .center, spacing: 10) {
                                    LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                                                  hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt, size: 30,
                                                  appearance: bot.supportedAppearance)
                                    Text(bot.name).font(.body)
                                        .foregroundStyle(isSelected || canSelectMore ? .primary : .secondary)
                                    Spacer(minLength: 0)
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.accentColor : (canSelectMore ? Color.secondary : Color.secondary.opacity(0.5)))
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
                            .disabled(!isSelected && !canSelectMore)
                            .accessibilityHint(isSelected ? "取消选择" : (canSelectMore ? "选择" : BotProductLimits.groupSelectionFullMessage))
                        }
                    }
                } header: {
                    Text(BotProductLimits.groupSelectionTitle(selectedCount: projectedCount))
                }
                if let error {
                    Section { ConnectionNotice(title: error) { Task { await load() } } }
                }
            }
            .disabled(saving)
            .navigationTitle("添加成员").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissToolbarButton(action: { dismiss() }).disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "添加中…" : "添加") {
                        guard canSubmit else { return }
                        saving = true
                        let ids = candidates.filter { selected.contains($0.id) }.map(\.id)
                        onConfirm(ids)
                    }
                    .disabled(!canSubmit)
                }
            }
            .task { await load() }
        }
    }

    private func toggle(_ botID: Int, isSelected: Bool) {
        if isSelected {
            selected.remove(botID)
            return
        }
        guard canSelectMore else { return }
        selected.insert(botID)
    }

    private func load() async {
        let generation = app.sessionGeneration; loading = true
        defer { if generation == app.sessionGeneration { loading = false } }
        do {
            let result = try await app.api.bots()
            guard generation == app.sessionGeneration, !Task.isCancelled else { return }
            bots = result.bots; error = nil
        } catch {
            if generation == app.sessionGeneration { self.error = app.message(for: error) }
        }
    }
}
