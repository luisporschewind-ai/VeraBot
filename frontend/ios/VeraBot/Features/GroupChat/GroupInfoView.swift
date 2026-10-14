import SwiftUI
import VeraBotCore
import VeraBotData
import VeraBotNetworking

struct GroupInfoView: View {
    @Bindable var model: GroupChatViewModel
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var clearConfirm = false
    @State private var deleteConfirm = false
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("群聊名称") { TextField("名称", text: $name) }
                memberSection
                if model.busy { Section { Button("先停止当前讨论") { Task { await model.stop() } }.disabled(model.confirmingStop) } }
                Section {
                    Button("清空群历史", role: .destructive) { clearConfirm = true }
                    Button("删除群聊", role: .destructive) { deleteConfirm = true }
                }.disabled(model.busy || saving)
                if let error { Section { Text(error).foregroundStyle(.secondary) } }
            }.navigationTitle("群设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissToolbarButton(kind: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await perform {
                        try await model.update(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    } } }.disabled(saving || model.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 64)
                }
            }.onAppear { name = model.group.name }
            .confirmationDialog("清空本群历史？", isPresented: $clearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { Task { await perform { try await model.clear(); dismiss() } } }
            } message: { Text("仅删除本群聊天记录。") }
            .confirmationDialog("删除这个群聊？", isPresented: $deleteConfirm, titleVisibility: .visible) {
                Button("删除", role: .destructive) { Task { await perform { try await model.delete(); dismiss(); onDeleted() } } }
            } message: { Text("群和全部群历史将一起删除。") }
        }
    }
    private var memberSection: some View {
        Section {
            ForEach(model.group.members) { member in
                GroupInfoMemberRow(member: member)
                    .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
            }
        } header: {
            Text("群成员（\(model.group.members.count)）")
        } footer: {
            Text("成员共享本群文字记录；群聊不会读取私聊或长期记忆。")
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !saving else { return }; saving = true; defer { saving = false }
        do { try await action() } catch { self.error = (error as? APIError)?.status == 409 ? "讨论还在进行，请先停止后再操作。" : "暂时没能完成操作，请重新加载后再试。" }
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
        }
    }
}
