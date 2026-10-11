import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct GroupListView: View {
    @Environment(AppState.self) private var app
    @Binding var creating: Bool
    @State private var groups: [ChatGroup] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selected: ChatGroup?
    var body: some View {
        VStack {
            if loading && groups.isEmpty { BotLoadingView() }
            else if groups.isEmpty && error == nil {
                VStack(spacing: 14) {
                    RobotAvatarView(action: .waiting, size: 110, color: .brandFill, ambient: false)
                    Text("把伙伴们聚在一起").font(.title3.bold())
                    Text("聊一个话题，听听每个 Bot 的想法。").foregroundStyle(.secondary)
                    Button("创建群聊") { creating = true }.prominentButtonStyle()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(groups) { group in
                    Button { selected = group } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: -12) { ForEach(group.members.prefix(3)) { GroupMemberAvatar(member: $0, size: 32) } }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.name).font(.headline).foregroundStyle(.primary)
                                Text(group.lastMessage?.content.isEmpty == false ? group.lastMessage!.content : "从一句话开始讨论")
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Text(group.members.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let updated = group.updatedAt, let date = ISO8601DateFormatter().date(from: updated) {
                                Text(date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }.buttonStyle(.plain).plainListRow()
                }.listStyle(.plain)
            }
            if let error {
                VStack { Text(error); Button("重新加载") { Task { await load() } } }
                    .font(.footnote).padding()
            }
        }.themedPageBackground()
        .task(id: app.sessionGeneration) { groups = []; selected = nil; await load() }
        .refreshable { await load() }
        .sheet(isPresented: $creating) {
            CreateGroupSheet { group in creating = false; selected = group; Task { await load() } }
        }
        .navigationDestination(item: $selected) { group in
            GroupChatView(group: group, app: app).toolbar(.hidden, for: .tabBar)
        }
    }
    private func load() async {
        let generation = app.sessionGeneration; loading = true
        defer { if generation == app.sessionGeneration { loading = false } }
        do {
            let response = try await app.groupAPI.groups()
            guard generation == app.sessionGeneration, !Task.isCancelled else { return }
            groups = response.groups; error = nil
        } catch is CancellationError {} catch {
            if generation == app.sessionGeneration { self.error = "伙伴们暂时没连上，请重新加载。" }
        }
    }
}
