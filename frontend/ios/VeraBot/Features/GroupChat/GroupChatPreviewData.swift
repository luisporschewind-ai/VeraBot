#if DEBUG
import SwiftUI
import VeraBotCore

/// G0 only: in-memory fixtures. Never calls the backend or stores account data.
@MainActor
@Observable
final class GroupChatPreviewData {
    static let members = [
        ChatGroupMember(id: 1, botID: 1, name: "Vera", color: "#6461D1", detail: "陪你把想法聊清楚"),
        ChatGroupMember(id: 2, botID: 2, name: "小研", color: "#3D7A8C", detail: "喜欢探索与不同视角"),
        ChatGroupMember(id: 3, botID: 3, name: "阿厨", color: "#D48A54", detail: "把生活安排得有滋有味"),
        ChatGroupMember(id: 4, botID: 4, name: "小艺", color: "#B96D96", detail: "寻找有趣的灵感")
    ]
    var groups: [ChatGroup] = [
        ChatGroup(id: 1, name: "周末小分队", members: Array(members.prefix(3)), defaultMemberID: 1)
    ]
    var messages: [Int: [GroupMessage]] = [
        1: [
            GroupMessage(id: 1, memberID: nil, content: "周末想放松一下，你们有什么想法？"),
            GroupMessage(id: 2, memberID: 1, content: "留半天给自己吧。**不用赶行程**，找一件你真的想做的小事就好。"),
            GroupMessage(id: 3, memberID: 2, content: "接着 Vera 的想法，我想加一点探索：去一条没走过的街，看看书店或小展览。"),
            GroupMessage(id: 4, memberID: 3, content: "那我负责吃的！逛完一起做顿简单的晚饭，让周末有个舒服的收尾。")
        ]
    ]
    private var nextGroupID = 2
    private var nextMessageID = 10

    func create(name: String, memberIDs: Set<Int>, defaultID: Int) -> ChatGroup {
        let selected = Self.members.filter { memberIDs.contains($0.id) }
        let group = ChatGroup(id: nextGroupID, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                              members: selected, defaultMemberID: defaultID)
        nextGroupID += 1
        groups.append(group)
        messages[group.id] = []
        return group
    }

    @discardableResult
    func append(groupID: Int, memberID: Int?, text: String, status: GroupMessageStatus = .completed) -> Int {
        let id = nextMessageID
        nextMessageID += 1
        messages[groupID, default: []].append(GroupMessage(id: id, memberID: memberID, content: text, status: status))
        return id
    }

    func update(groupID: Int, messageID: Int, text: String? = nil, status: GroupMessageStatus? = nil) {
        guard let index = messages[groupID]?.firstIndex(where: { $0.id == messageID }) else { return }
        if let text { messages[groupID]?[index].content = text }
        if let status { messages[groupID]?[index].status = status }
    }

    func rename(groupID: Int, name: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remove(groupID: Int) {
        groups.removeAll { $0.id == groupID }
        messages[groupID] = nil
    }
}

struct GroupPreviewLabel: View {
    var body: some View {
        Label("界面预览 · 模拟数据", systemImage: "viewfinder")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(Color.sectionFill)
    }
}

/// A Debug launch route lets the user inspect the prototype without logging in.
struct GroupChatPreviewRoot: View {
    @State private var data = GroupChatPreviewData()
    var body: some View {
        NavigationStack {
            PreviewGroupListView(data: data, initialGroupID:
                ProcessInfo.processInfo.arguments.contains("--group-chat-preview-detail") ? 1 : nil)
                .navigationTitle("群聊")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("伙伴讨论").font(.caption).foregroundStyle(.secondary)
                    }
                }
        }
    }
}
#endif
