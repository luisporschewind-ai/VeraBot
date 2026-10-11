#if DEBUG
import SwiftUI
import VeraBotCore

struct PreviewGroupChatView: View {
    let groupID: Int
    let data: GroupChatPreviewData
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var targetID: Int?
    @State private var round = false
    @State private var activeID: Int?
    @State private var activeMessageID: Int?
    @State private var task: Task<Void, Never>?
    @State private var runID = UUID()
    @State private var scrollTick = 0
    @State private var simulateFailure = false
    @State private var rename = false
    @State private var newName = ""
    @State private var clearConfirm = false
    @State private var deleteConfirm = false

    private var group: ChatGroup? { data.groups.first { $0.id == groupID } }
    private var messages: [GroupMessage] { data.messages[groupID] ?? [] }
    private var sending: Bool { task != nil }
    private var selectedMember: ChatGroupMember? {
        group?.members.first { $0.id == (targetID ?? group?.defaultMemberID) }
    }

    var body: some View {
        VStack(spacing: 0) {
            GroupPreviewLabel()
            if let group {
                memberStrip(group)
                timeline(group)
                composer(group)
            }
        }
        .themedPageBackground()
        .navigationTitle(group?.name ?? "群聊")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("重命名", systemImage: "pencil") {
                        newName = group?.name ?? ""
                        rename = true
                    }.disabled(sending)
                    Toggle("演示下一次回应失败", isOn: $simulateFailure).disabled(sending)
                    Button("清空预览消息", systemImage: "eraser") { clearConfirm = true }.disabled(sending)
                    Button("删除预览群", systemImage: "trash", role: .destructive) { deleteConfirm = true }.disabled(sending)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("重命名群聊", isPresented: $rename) {
            TextField("群聊名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("保存") { data.rename(groupID: groupID, name: newName) }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newName.count > 64)
        }
        .confirmationDialog("清空预览消息？", isPresented: $clearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) { data.messages[groupID] = [] }
        } message: { Text("保留群和成员，删除本次运行中的模拟聊天记录。") }
        .confirmationDialog("删除预览群？", isPresented: $deleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { data.remove(groupID: groupID); dismiss() }
        } message: { Text("群和模拟聊天记录将一起删除。") }
        .onDisappear { stop() }
        .onChange(of: scenePhase) { _, value in if value != .active { stop() } }
    }

    private func memberStrip(_ group: ChatGroup) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(group.members) { member in
                    Button {
                        targetID = member.id
                        round = false
                    } label: {
                        HStack(spacing: 5) {
                            GroupMemberAvatar(member: member, size: 32, action: activeID == member.id ? .thinking : .idle)
                            Text(member.name).font(.subheadline)
                            if activeID == member.id { Text("回应中").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(!round && selectedMember?.id == member.id ? Color.brandSoft : Color.sectionFill,
                                    in: Capsule())
                    }.buttonStyle(.plain).disabled(sending)
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func timeline(_ group: ChatGroup) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if messages.isEmpty {
                        VStack(spacing: 12) {
                            RobotAvatarView(action: .waiting, size: 96, color: .brandFill, ambient: false)
                            Text("你想和伙伴们聊什么？").font(.headline)
                            Text("点名一位伙伴，或让大家轮流说说想法。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("聊聊周末安排") { draft = "周末想放松一下，大家有什么想法？"; round = true }
                                .buttonStyle(.bordered)
                        }.frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    ForEach(messages) { message in bubble(message, group: group).id(message.id) }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollTick) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func bubble(_ message: GroupMessage, group: ChatGroup) -> some View {
        if let member = group.members.first(where: { $0.id == message.memberID }) {
            HStack(alignment: .top, spacing: 10) {
                GroupMemberAvatar(member: member, size: 42,
                                  action: message.status == .failed ? .warning : message.status == .streaming ? .replying : .idle)
                VStack(alignment: .leading, spacing: 6) {
                    Text(member.name).font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        if message.content.isEmpty && message.status == .streaming {
                            HStack { ProgressView(); Text("正在组织想法…").font(.subheadline).foregroundStyle(.secondary) }
                        } else { MessageContentView(text: message.content).textSelection(.enabled) }
                        if message.status == .failed {
                            Button("再试一次", systemImage: "arrow.clockwise") { send(retryMemberID: member.id) }
                                .font(.subheadline).disabled(sending)
                        }
                        if message.status == .stopped {
                            Label("已停止 · 回应未完成", systemImage: "stop.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(13).background(Color.botBubble, in: RoundedRectangle(cornerRadius: 18))
                }
                Spacer(minLength: 20)
            }
        } else {
            HStack {
                Spacer(minLength: 55)
                Text(message.content).textSelection(.enabled).padding(13)
                    .foregroundStyle(Color.userBubbleText)
                    .background(Color.userBubble, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func composer(_ group: ChatGroup) -> some View {
        VStack(spacing: 10) {
            HStack {
                Menu {
                    ForEach(group.members) { member in
                        Button("@\(member.name)") { targetID = member.id; round = false }
                    }
                    Button("大家讨论", systemImage: "person.3") { round = true }
                } label: {
                    Label(round ? "大家讨论" : (selectedMember?.name ?? "伙伴"),
                          systemImage: round ? "person.3" : "at")
                        .font(.subheadline.weight(.medium))
                }.disabled(sending)
                Spacer()
                if sending {
                    Button("停止", systemImage: "stop.fill") { stop() }
                        .font(.subheadline).tint(.red)
                } else {
                    Button { round.toggle() } label: {
                        Text(round ? "切换单人回应" : "大家讨论").font(.caption)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("想聊点什么？", text: $draft, axis: .vertical)
                    .lineLimit(1...4).padding(12)
                    .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("group-message-input")
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.headline)
                        .frame(width: 44, height: 44).foregroundStyle(.white)
                        .background(Color.brandFill, in: Circle())
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
                .opacity(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000 ? 0.4 : 1)
                .accessibilityLabel("发送")
            }
            Text(sending ? "伙伴按顺序回应，你可以随时停止" : "预览回应为固定示例，不调用模型")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .background(Color.appBackground)
    }

    private func send(retryMemberID: Int? = nil) {
        guard !sending, let group else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard retryMemberID != nil || (!text.isEmpty && text.count <= 2000) else { return }
        let speakers = retryMemberID.map { id in group.members.filter { $0.id == id } }
            ?? (round ? group.members : group.members.filter { $0.id == selectedMember?.id })
        if retryMemberID == nil {
            data.append(groupID: groupID, memberID: nil, text: text)
            draft = ""
        }
        let failureID = simulateFailure ? speakers.dropFirst().first?.id ?? speakers.first?.id : nil
        simulateFailure = false
        let serial = UUID()
        runID = serial
        task = Task { @MainActor in
            for member in speakers {
                guard !Task.isCancelled, runID == serial else { return }
                activeID = member.id
                let mid = data.append(groupID: groupID, memberID: member.id, text: "", status: .streaming)
                activeMessageID = mid
                scrollTick += 1
                do {
                    try await Task.sleep(for: .milliseconds(900))
                    if member.id == failureID {
                        data.update(groupID: groupID, messageID: mid,
                                    text: "这次回应暂时没准备好。你可以让其他伙伴先说，稍后再试。",
                                    status: .failed)
                    } else {
                        let reply = exampleReply(memberID: member.id, retry: retryMemberID != nil)
                        var partial = ""
                        for chunk in reply.map(String.init) {
                            try await Task.sleep(for: .milliseconds(32))
                            guard runID == serial else { return }
                            partial += chunk
                            data.update(groupID: groupID, messageID: mid, text: partial)
                            scrollTick += 1
                        }
                        data.update(groupID: groupID, messageID: mid, status: .completed)
                    }
                    activeMessageID = nil
                } catch { return }
            }
            guard runID == serial else { return }
            activeID = nil
            task = nil
            scrollTick += 1
        }
        scrollTick += 1
    }

    private func stop() {
        runID = UUID()
        task?.cancel()
        task = nil
        if let activeMessageID {
            data.update(groupID: groupID, messageID: activeMessageID, status: .stopped)
        }
        activeMessageID = nil
        activeID = nil
        scrollTick += 1
    }

    private func exampleReply(memberID: Int, retry: Bool) -> String {
        if retry { return "这次可以继续啦。先挑一个最想尝试的想法，我们再一起把它聊具体。" }
        switch memberID {
        case 1: return "我先开个头：**给自己留一点余地**。不用一次安排太多，挑一件期待的小事就很好。"
        case 2: return "接着刚才的想法，我想加一点探索。试试一个新地方，也给临时发现留些时间。"
        case 3: return "我来补一点生活气！准备喜欢的食物，留个舒服的收尾，让这件事更值得期待。"
        default: return "我想给这个计划添点灵感：拍一张照片，或记下一个有趣瞬间，留作我们的小纪念。"
        }
    }
}
#endif
