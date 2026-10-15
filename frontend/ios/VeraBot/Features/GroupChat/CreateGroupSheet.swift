import SwiftUI
import VeraBotCore

struct CreateGroupSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onCreated: (ChatGroup) -> Void
    @State private var name = ""
    @State private var bots: [Bot] = []
    @State private var selected: Set<Int> = []
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool {
        !saving && !loading && !trimmed.isEmpty && trimmed.count <= 64
            && BotProductLimits.canCreateGroup(selectedBotCount: selected.count)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("群聊名称") { TextField("例如：周末小分队", text: $name) }
                Section {
                    if loading { ProgressView() }
                    ForEach(bots) { bot in
                        let isSelected = selected.contains(bot.id)
                        let canSelectMore = BotProductLimits.canAddBotToSelection(selectedCount: selected.count)
                        Button {
                            toggle(bot.id, isSelected: isSelected, canSelectMore: canSelectMore)
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
                } header: {
                    Text(BotProductLimits.groupSelectionTitle(selectedCount: selected.count))
                }
                if let error { Section { Text(error).foregroundStyle(.secondary); Button("重新加载伙伴") { Task { await load() } } } }
            }.disabled(saving)
            .navigationTitle("创建群聊").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissToolbarButton(action: { dismiss() }).disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "创建中…" : "创建") { Task { await create() } }
                        .disabled(!canSubmit)
                }
            }.task { await load() }
        }
    }

    private func toggle(_ botID: Int, isSelected: Bool, canSelectMore: Bool) {
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
        } catch { if generation == app.sessionGeneration { self.error = "暂时无法加载伙伴，请再试一次。" } }
    }
    private func create() async {
        guard !saving else { return }
        // 提交时二次校验：防止重复触发绕过 2～5 范围。
        guard BotProductLimits.canCreateGroup(selectedBotCount: selected.count) else { return }
        saving = true
        let generation = app.sessionGeneration
        defer { if generation == app.sessionGeneration { saving = false } }
        do {
            let ids = bots.filter { selected.contains($0.id) }.map(\.id)
            let group = try await app.groupAPI.createGroup(GroupCreateRequest(name: trimmed, botIDs: ids))
            guard generation == app.sessionGeneration, !Task.isCancelled else { return }
            dismiss(); onCreated(group)
        } catch { if generation == app.sessionGeneration { self.error = "暂时无法创建群聊，请检查伙伴和群数量后再试。" } }
    }
}
