import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct GroupInfoView: View {
    @Bindable var model: GroupChatViewModel
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var target = 0
    @State private var clearConfirm = false
    @State private var deleteConfirm = false
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("群聊名称") { TextField("名称", text: $name) }
                Section("默认回应者") {
                    Picker("伙伴", selection: $target) { ForEach(model.group.members.filter { $0.available }) { Text($0.name).tag($0.botID ?? 0) } }
                }
                Section { ForEach(model.group.members) { Text($0.name + ($0.available ? "" : " · 不可用")) } }
                    footer: { Text("成员共享本群文字记录；群聊不会读取私聊或长期记忆。") }
                if model.busy { Section { Button("先停止当前讨论") { Task { await model.stop() } }.disabled(model.confirmingStop) } }
                Section {
                    Button("清空群历史", role: .destructive) { clearConfirm = true }
                    Button("删除群聊", role: .destructive) { deleteConfirm = true }
                }.disabled(model.busy || saving)
                if let error { Section { Text(error).foregroundStyle(.secondary) } }
            }.navigationTitle("群设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await perform {
                        try await model.update(name: name.trimmingCharacters(in: .whitespacesAndNewlines), defaultBotID: target > 0 ? target : nil)
                        dismiss()
                    } } }.disabled(saving || model.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 64)
                }
            }.onAppear { name = model.group.name; target = model.group.defaultBotID ?? 0 }
            .confirmationDialog("清空本群历史？", isPresented: $clearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { Task { await perform { try await model.clear(); dismiss() } } }
            } message: { Text("仅删除本群聊天记录。") }
            .confirmationDialog("删除这个群聊？", isPresented: $deleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) { Task { await perform { try await model.delete(); dismiss(); onDeleted() } } }
            } message: { Text("群和全部群历史将一起删除。") }
        }
    }
    private func perform(_ action: () async throws -> Void) async {
        guard !saving else { return }; saving = true; defer { saving = false }
        do { try await action() } catch { self.error = (error as? APIError)?.status == 409 ? "讨论还在进行，请先停止后再操作。" : "暂时没能完成操作，请重新加载后再试。" }
    }
}
