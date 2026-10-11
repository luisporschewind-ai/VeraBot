import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct GroupChatView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var model: GroupChatViewModel
    @State private var round = false
    @State private var info = false
    private let app: AppState
    private let preferenceKey: String
    init(group: ChatGroup, app: AppState) {
        self.app = app
        let generation = app.sessionGeneration
        _model = State(initialValue: GroupChatViewModel(group: group, api: app.groupAPI, sessionIsCurrent: { app.sessionGeneration == generation }))
        preferenceKey = "groupTarget.\(app.baseURLString).\(app.userID ?? 0).\(group.id)"
    }
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(model.group.members) { member in
                        Button { model.preferredBotID = member.botID; round = false } label: {
                            VStack(spacing: 4) {
                                GroupMemberAvatar(member: member, size: 42, action: model.state.activeMemberID == member.id ? .replying : .idle)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                                Text(member.name).font(.caption).foregroundStyle(member.botID == model.preferredBotID ? Color.brandAccent : Color.secondary)
                                if !member.available { Text("不可用").font(.caption2).foregroundStyle(.secondary) }
                            }
                            .padding(8)
                            .background(!round && member.botID == model.preferredBotID ? Color.brandAccent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.busy || !member.available)
                            .accessibilityLabel("点名 " + member.name)
                            .accessibilityHint("选择后发送消息，由这位伙伴回应")
                    }
                }.padding()
            }.background(Color.sectionFill)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if model.nextBeforeID != nil { Button("加载更早的消息") { Task { await model.loadOlder() } }.disabled(model.loading) }
                        if model.loading && model.state.messages.isEmpty { BotLoadingView() }
                        if !model.loading && model.state.messages.isEmpty {
                            RobotAvatarView(action: .waiting, size: 90, color: .brandFill, ambient: false)
                            Text("从一个话题开始").foregroundStyle(.secondary)
                        }
                        ForEach(model.state.messages) { message in bubble(message).id(message.id) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding()
                }.scrollDismissesKeyboard(.interactively)
                .onChange(of: model.state.messages.last?.content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: model.state.messages.count) { old, new in if new > old && model.busy { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            if let error = model.errorMessage {
                HStack { Image(systemName: "exclamationmark.bubble"); Text(error); Button("重新加载") { Task { await model.load() } } }
                    .font(.footnote).padding(10).background(Color.sectionFill)
            }
            if model.confirmingStop { Text("正在确认讨论已停止…").font(.caption).foregroundStyle(.secondary) }
            if model.group.readOnly { Text("群里已没有可用伙伴，仍可查看历史。").font(.footnote).padding() }
            else {
                HStack {
                    Menu { Button("一位回应") { round = false }; Button("大家讨论") { round = true } }
                    label: { Text(round ? "大家讨论" : "@\(model.group.members.first { $0.botID == model.preferredBotID }?.name ?? "伙伴")").font(.caption) }
                    .disabled(model.busy)
                    TextField("聊点什么…", text: $model.draft, axis: .vertical).lineLimit(1...5)
                    if model.busy {
                        Button("停止", systemImage: "stop.fill") { Task { await model.stop() } }.disabled(model.confirmingStop)
                    } else {
                        Button("发送", systemImage: "arrow.up.circle.fill") {
                            model.send(text: model.draft, mode: round ? .round : .single, targetBotID: model.preferredBotID)
                        }.disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draft.count > 2000 || model.loading)
                    }
                }.padding().background(Color.appBackground)
            }
        }.themedPageBackground().navigationTitle(model.group.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("群设置", systemImage: "ellipsis") { info = true } } }
        .sheet(isPresented: $info) { GroupInfoView(model: model) { dismiss() } }
        .task { let stored = UserDefaults.standard.integer(forKey: preferenceKey); if stored > 0 { model.preferredBotID = stored }; await model.load() }
        .onChange(of: model.preferredBotID) { _, value in if let value { UserDefaults.standard.set(value, forKey: preferenceKey) } }
        .onChange(of: phase) { _, value in if value != .active { model.leave() } else { Task { await model.load() } } }
        .onChange(of: app.sessionGeneration) { _, _ in model.leave() }
        .onDisappear { model.leave() }
    }
    @ViewBuilder private func bubble(_ message: GroupMessage) -> some View {
        if message.role == .user {
            HStack { Spacer(minLength: 50); Text(message.content).textSelection(.enabled).padding(13)
                .foregroundStyle(Color.userBubbleText).background(Color.userBubble, in: RoundedRectangle(cornerRadius: 18)) }
        } else {
            HStack(alignment: .top, spacing: 10) {
                if let member = historicalMember(message) { GroupMemberAvatar(member: member, size: 40, action: message.status == .failed ? .warning : message.status == .streaming ? .replying : .idle) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.senderName ?? historicalMember(message)?.name ?? "伙伴").font(.caption).foregroundStyle(.secondary)
                    if message.retryOfMessageID != nil { Text("重试回应").font(.caption2).foregroundStyle(.secondary) }
                    if message.content.isEmpty && message.status == .streaming { ProgressView("正在组织想法…") }
                    else { MessageContentView(text: message.content).textSelection(.enabled) }
                    if message.status != .completed && message.status != .streaming {
                        Text(message.status == .failed ? "回应暂未完成" : message.status == .stopped ? "已停止 · 回应未完成" : "连接中断 · 回应未完成").font(.caption).foregroundStyle(.secondary)
                        Button("再试一次", systemImage: "arrow.clockwise") { model.retry(messageID: message.id) }
                            .font(.caption).disabled(model.busy || !(model.group.members.first { $0.id == message.memberID }?.available ?? false))
                    }
                }.padding(13).background(Color.botBubble, in: RoundedRectangle(cornerRadius: 18))
                Spacer(minLength: 20)
            }
        }
    }
    private func historicalMember(_ message: GroupMessage) -> ChatGroupMember? {
        if let snapshot = message.senderAppearance, let data = try? JSONEncoder().encode(snapshot), let member = try? JSONDecoder().decode(ChatGroupMember.self, from: data) { return member }
        return model.group.members.first { $0.id == message.memberID }
    }
}
