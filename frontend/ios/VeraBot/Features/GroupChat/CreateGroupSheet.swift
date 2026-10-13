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
    var body: some View {
        NavigationStack {
            Form {
                Section("群聊名称") { TextField("例如：周末小分队", text: $name) }
                Section("选择伙伴 · \(selected.count)/4") {
                    if loading { ProgressView() }
                    ForEach(bots) { bot in
                        Button {
                            if selected.contains(bot.id) { selected.remove(bot.id) }
                            else if selected.count < 4 { selected.insert(bot.id) }
                        } label: {
                            HStack {
                                LiveBotAvatar(botID:bot.id,emoji:bot.avatar,color:bot.color,
                                              hasAvatar:bot.hasAvatar,updatedAt:bot.avatarUpdatedAt,size:40,
                                              appearance:bot.supportedAppearance)
                                Text(bot.name).foregroundStyle(.primary)
                                Spacer(); Image(systemName: selected.contains(bot.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Section { Text("选择 2–4 位伙伴。系统会根据每条消息的意图分配回应者；成员共享本群聊天记录。") }
                if let error { Section { Text(error).foregroundStyle(.secondary); Button("重新加载伙伴") { Task { await load() } } } }
            }.disabled(saving)
            .navigationTitle("创建群聊").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissToolbarButton(action: { dismiss() }).disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "创建中…" : "创建") { Task { await create() } }
                        .disabled(saving || loading || trimmed.isEmpty || trimmed.count > 64 || !(2...4).contains(selected.count))
                }
            }.task { await load() }
        }
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
        guard !saving else { return }; saving = true
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
