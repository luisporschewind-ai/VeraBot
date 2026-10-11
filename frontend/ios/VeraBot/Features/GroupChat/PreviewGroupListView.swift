#if DEBUG
import SwiftUI
import VeraBotCore

struct PreviewGroupListView: View {
    let data: GroupChatPreviewData
    var initialGroupID: Int? = nil
    @State private var creating = false
    @State private var selectedGroup: ChatGroup?
    @State private var pendingDelete: ChatGroup?
    @State private var openedInitial = false

    var body: some View {
        VStack(spacing: 0) {
            GroupPreviewLabel()
            if data.groups.isEmpty {
                VStack(spacing: 14) {
                    RobotAvatarView(action: .waiting, size: 110, color: .brandFill, ambient: false)
                    Text("把伙伴们聚在一起").font(.title3.bold())
                    Text("聊一个话题，听听每个 Bot 的想法。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("创建群聊") { creating = true }.prominentButtonStyle()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(data.groups) { group in
                            Button { selectedGroup = group } label: {
                                GroupListRow(group: group, last: data.messages[group.id]?.last)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("删除", systemImage: "trash") { pendingDelete = group }.tint(.red)
                            }
                            .plainListRow()
                        }
                    } footer: {
                        Text("预览群只保留在本次运行中，不会改动你的 Bot 或聊天记录。")
                    }
                }.listStyle(.plain)
            }
            Button { creating = true } label: {
                Label("创建群聊", systemImage: "plus.bubble").frame(maxWidth: .infinity)
            }
            .prominentButtonStyle().padding()
            .disabled(data.groups.count >= 10)
        }
        .themedPageBackground()
        .task {
            guard !openedInitial else { return }
            openedInitial = true
            if let initialGroupID {
                selectedGroup = data.groups.first { $0.id == initialGroupID }
            }
        }
        .sheet(isPresented: $creating) {
            PreviewCreateGroupSheet(data: data) { selectedGroup = $0 }
        }
        .navigationDestination(item: $selectedGroup) { group in
            PreviewGroupChatView(groupID: group.id, data: data).toolbar(.hidden, for: .tabBar)
        }
        .confirmationDialog("删除这个预览群？", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let pendingDelete { data.remove(groupID: pendingDelete.id) }
                pendingDelete = nil
            }
        } message: { Text("该预览群的模拟消息将一起删除。") }
    }
}

private struct GroupListRow: View {
    let group: ChatGroup
    let last: GroupMessage?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color.brandSoft).frame(width: 62, height: 62)
                HStack(spacing: -12) {
                    ForEach(group.members.prefix(3)) { member in
                        GroupMemberAvatar(member: member, size: 32)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(group.name).font(.headline)
                    Spacer()
                    Text("\(group.members.count) 位伙伴").font(.caption).foregroundStyle(.secondary)
                }
                Text(last?.content ?? "从一句话开始新的讨论")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(group.members.map(\.name).joined(separator: " · "))
                    .font(.caption).foregroundStyle(Color.brandAccent)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 10)
    }
}
#endif
