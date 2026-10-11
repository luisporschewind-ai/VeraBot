#if DEBUG
import SwiftUI
import VeraBotCore

struct PreviewCreateGroupSheet: View {
    let data: GroupChatPreviewData
    let onCreated: (ChatGroup) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<Int> = [1, 2, 3]
    @State private var defaultID = 1

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { !trimmed.isEmpty && trimmed.count <= 64 && (2...4).contains(selected.count) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：周末小分队", text: $name)
                        .accessibilityIdentifier("group-name")
                } header: { Text("群聊名称") }
                Section {
                    ForEach(GroupChatPreviewData.members) { member in
                        Button {
                            if selected.contains(member.id) { selected.remove(member.id) }
                            else { selected.insert(member.id) }
                            if !selected.contains(defaultID) {
                                defaultID = GroupChatPreviewData.members.first(where: { selected.contains($0.id) })?.id ?? 0
                            }
                        } label: {
                            HStack(spacing: 12) {
                                GroupMemberAvatar(member: member)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(member.name).foregroundStyle(.primary)
                                    Text(member.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(member.id) ? Color.brand : Color.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                } header: { Text("选择伙伴 · \(selected.count)/4") }
                footer: { Text("选择 2–4 位伙伴。这里使用示例 Bot，不会创建或修改真实 Bot。") }
                Section {
                    if selected.isEmpty {
                        Text("先选两位伙伴").foregroundStyle(.secondary)
                    } else {
                        Picker("默认回应者", selection: $defaultID) {
                            ForEach(GroupChatPreviewData.members.filter { selected.contains($0.id) }) { member in
                                Text(member.name).tag(member.id)
                            }
                        }
                    }
                } footer: {
                    Text("普通消息由一位伙伴回应；点名或「大家讨论」时按你的选择发言。")
                }
                Section { GroupPreviewLabel() }
            }
            .navigationTitle("创建群聊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let group = data.create(name: trimmed, memberIDs: selected, defaultID: defaultID)
                        dismiss()
                        onCreated(group)
                    }.disabled(!valid || data.groups.count >= 10)
                }
            }
        }
    }
}
#endif
