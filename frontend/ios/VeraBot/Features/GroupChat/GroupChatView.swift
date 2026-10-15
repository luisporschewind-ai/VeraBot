import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VeraBotCore
import VeraBotData
import VeraBotNetworking
import VeraBotTTS

struct GroupChatView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var model: GroupChatViewModel
    @State private var attachment: ComposerAttachmentModel
    @State private var notificationViewport: CGSize = .zero
    @State private var notificationFrames: [Int: CGRect] = [:]
    @State private var viewport: CGRect = .zero
    @State private var composerViewport: CGRect = .zero
    @State private var pageVisible = false
    @State private var reading = ConversationReadingSession()
    @State private var entered = false
    @State private var initialPositionReady = false
    @State private var followsBottom = true
    @State private var bottomAnchor: CGRect = .zero   // 只在 updateFollowsBottom 里读，避免滚动时整页重算 body
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var cameraDenied = false
    @State private var speech = SpeechInput()
    @State private var speechBase = ""
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var mentionTokens: [GroupMentionToken] = []
    @State private var replyToMessageID: Int?
    @State private var draftSelection = NSRange(location: 0, length: 0)
    @State private var inputFocused = false
    @State private var isComposingMention = false
    @Environment(SpeechPlayer.self) private var player
    @State private var info = false
    private let app: AppState
    private let onGroupUpdated: ((ChatGroup) -> Void)?
    private let legacyPreferenceKey: String
    let highlightMessageID: Int?
    init(group: ChatGroup, app: AppState, highlightMessageID: Int? = nil, onGroupUpdated: ((ChatGroup) -> Void)? = nil) {
        self.app = app
        self.highlightMessageID = highlightMessageID
        self.onGroupUpdated = onGroupUpdated
        legacyPreferenceKey = "groupTarget.\(app.baseURLString).\(app.userID ?? 0).\(group.id)"
        let generation = app.sessionGeneration
        let session = app.authSession
        let endpoint = app.baseURLString
        _model = State(initialValue: GroupChatViewModel(group: group, api: app.groupAPI,
                                                        repository: app.conversationRepository,
                                                        sessionIsCurrent: { session.isCurrent(generation) && app.baseURLString == endpoint }))
        _attachment = State(initialValue: ComposerAttachmentModel(botID: nil, api: app.api))
    }
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        LazyVStack(spacing: 16) {
                            GroupExecutionStatusView(model: model)
                            if model.nextBeforeID != nil { Button("加载更早的消息") { Task { await model.loadOlder() } }.disabled(model.loading) }
                            if model.loading && model.state.messages.isEmpty { BotLoadingView() }
                            if !model.loading && model.state.messages.isEmpty && !model.historyIncomplete && model.errorMessage == nil {
                                RobotAvatarView(action: .waiting, size: 90, color: .brandFill, ambient: false)
                                Text("从一个话题开始").foregroundStyle(.secondary)
                            }
                            ForEach(model.state.messages) { message in
                                messageCell(message)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .conversationBottomAnchor { bottomAnchor = $0; updateFollowsBottom() }
                    }.padding()
                }
                .conversationViewport($viewport)
                .onChange(of: effectiveViewport) { updateFollowsBottom() }
                .coordinateSpace(name: "notificationChatViewport")
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { notificationViewport = geometry.size; updateNotificationVisibility() }
                            .onChange(of: geometry.size) { _, size in notificationViewport = size; updateNotificationVisibility() }
                    }
                }
                .onPreferenceChange(GroupNotificationFrames.self) { frames in
                    notificationFrames = frames; updateNotificationVisibility()
                }
                .bottomAnchoredScrolling()
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { inputFocused = false }
                .background(Color.appBackground)
                .onChange(of: model.state.messages.last?.content) { _, _ in
                    guard initialPositionReady else { return }
                    if !entered && !model.state.messages.isEmpty {
                        if let first = highlightMessageID ?? reading.dividerMessageID { proxy.scrollTo(first, anchor: .center) }
                        else { proxy.scrollTo("bottom", anchor: .bottom) }
                        entered = true
                    } else if followsBottom { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: initialPositionReady) { _, ready in
                    guard ready, !entered else { return }
                    if let first = highlightMessageID ?? reading.dividerMessageID { proxy.scrollTo(first, anchor: .center) }
                    else { proxy.scrollTo("bottom", anchor: .bottom) }
                    entered = true
                }
                .onChange(of: model.state.messages.count) { old, new in if new > old && model.busy && followsBottom { proxy.scrollTo("bottom", anchor: .bottom) } }
                .overlay(alignment: .bottomTrailing) {
                    JumpToLatestButton(visible: !followsBottom) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }
            }
            if model.confirmingStop { Text("正在确认讨论已停止…").font(.caption).foregroundStyle(.secondary) }
        }
        .bottomBar {
            VStack(spacing: 8) {
                groupNotice
                if model.group.readOnly {
                    Text("群里已没有可用伙伴，仍可查看历史。")
                        .font(.footnote).padding(.horizontal).padding(.vertical, 12)
                        .frame(maxWidth: .infinity).background(Color.appBackground)
                } else {
                    composer
                }
            }.conversationComposer($composerViewport)
        }
        .themedPageBackground().navigationTitle(model.group.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                groupTitleButton.glassButtonStyle().buttonBorderShape(.capsule)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("群设置", systemImage: "ellipsis") { inputFocused = false; info = true }
            }
        }
        .sheet(isPresented: $info) {
            GroupInfoView(model: model, onGroupUpdated: onGroupUpdated) { dismiss() }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .plainText, .commaSeparatedText,
            UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { attachment.pickFile(url) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            attachment.pick(item)
            photoItem = nil
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { attachment.pick($0) }.ignoresSafeArea()
        }
        .alert("无法使用相机", isPresented: $cameraDenied) {
            Button("前往设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            Button("取消", role: .cancel) {}
        } message: { Text("请在「设置」中允许 VeraBot 使用相机。") }
        .task {
            pageVisible = true; await app.refreshActivityForEntry()
            if !entered { initialPositionReady = false; reading.enter(app.activity(kind: "group", id: model.group.id)?.unreadMessages ?? []) }
            UserDefaults.standard.removeObject(forKey: legacyPreferenceKey); await model.load()
            if !entered, let target = highlightMessageID ?? reading.dividerMessageID {
                while !model.state.messages.contains(where: { $0.id == target }), model.nextBeforeID != nil {
                    let before = model.nextBeforeID; await model.loadOlder(); if model.nextBeforeID == before { break }
                }
            }
            initialPositionReady = true
            updateNotificationVisibility()
            await app.markConversationRead(kind: "group", id: model.group.id)
        }
        .onChange(of: model.draft) { _, new in
            if new.isEmpty {
                mentionTokens = []
                replyToMessageID = nil
                draftSelection = NSRange(location: 0, length: 0)
            }
            draftSaveTask?.cancel()
            draftSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await model.saveDraft(new)
            }

        }
        .onChange(of: speech.transcript) { _, transcript in
            guard speech.isRecording || !transcript.isEmpty else { return }
            model.draft = speechBase + transcript
            draftSelection = NSRange(location: (model.draft as NSString).length, length: 0)
        }
        .onChange(of: notificationModalShown) { _, _ in updateNotificationVisibility() }
        .onChange(of: phase) { _, value in
            if value != .active { inputFocused = false; model.leave(); speech.cancel() } else { Task { await model.load() } }
            updateNotificationVisibility()
        }
        .onChange(of: app.activity(kind: "group", id: model.group.id)?.revision) { _, _ in if pageVisible { reading.include(app.activity(kind: "group", id: model.group.id)?.unreadMessages ?? []) } }
        .onChange(of: app.sessionGeneration) { _, _ in pageVisible = false; reading.leave(); model.leave() }
        .onDisappear {
            pageVisible = false
            if app.notificationEvents.visibleGroupID == model.group.id {
                app.notificationEvents.visibleGroupID = nil
                app.notificationEvents.visibleMessageIDs = []
            }
            if !hasTemporaryCover { reading.leave(); entered = false; let groupID = model.group.id; Task { await app.markConversationRead(kind: "group", id: groupID) } }
            inputFocused = false
            draftSaveTask?.cancel()
            let finalDraft = model.draft
            Task { await model.saveDraft(finalDraft) }
            model.leave(); speech.cancel()
        }
    }
    @ViewBuilder private var groupNotice: some View {
        if let error = model.errorMessage {
            if error.contains("暂未确认") || error.contains("待确认") || error.contains("待同步") {
                ConnectionNotice(title: error).padding(.horizontal, 16)
            } else if error.contains("暂时没连上") {
                ConnectionNotice(message: model.state.messages.isEmpty ? nil : "仍可查看已同步的历史。") {
                    Task { await model.load() }
                }
                .padding(.horizontal, 16)
            } else {
                ConnectionNotice(title: error, retry: { Task { await model.load() } })
                    .padding(.horizontal, 16)
            }
        } else if model.historyIncomplete && !model.loading {
            ConnectionNotice(message: model.state.messages.isEmpty ? nil : "仍可查看已同步的历史。") {
                Task { await model.load() }
            }
            .padding(.horizontal, 16)
        }
    }

    private func messageCell(_ message: GroupMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if message.id == reading.dividerMessageID {
                NewMessagesDivider()
            }
            bubble(message)
                .conversationReadVisibility(viewport: effectiveViewport, enabled: canRead && message.role != .user, revision: message.publicationRevision ?? 0) {
                    let activity = app.activity(kind: "group", id: model.group.id)
                    let revision = message.publicationRevision ?? 0
                    await app.markVisible(kind: "group", id: model.group.id, generation: message.generation ?? activity?.generation ?? 1, message: MessagePublication(messageID: message.id, publicationRevision: revision))
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: GroupNotificationFrames.self,
                            value: [message.id: geometry.frame(in: .named("notificationChatViewport"))])
                    }
                }
        }
        .id(message.id)
    }
    private var effectiveViewport: CGRect {
        guard !composerViewport.isEmpty else { return viewport }
        return CGRect(x: viewport.minX, y: viewport.minY, width: viewport.width, height: max(0, min(viewport.maxY, composerViewport.minY) - viewport.minY))
    }
    private func updateFollowsBottom() {
        let next = ScrollBottomDetector.followsBottom(anchor: bottomAnchor, viewport: effectiveViewport, current: followsBottom)
        if next != followsBottom { followsBottom = next }
    }
    private var hasTemporaryCover: Bool { info || showPhotos || showFiles || showCamera || cameraDenied }
    private var notificationModalShown: Bool { hasTemporaryCover }
    private var canRead: Bool { pageVisible && phase == .active && app.selectedTab == 0 && !hasTemporaryCover }
    private func updateNotificationVisibility() {
        app.notificationEvents.visibleGroupID = model.group.id
        app.notificationEvents.visibleBotID = nil
        guard phase == .active, !notificationModalShown else { app.notificationEvents.visibleMessageIDs = []; return }
        let bounds = CGRect(origin: .zero, size: notificationViewport)
        app.notificationEvents.visibleMessageIDs = Set(notificationFrames.filter { $0.value.intersects(bounds) }.keys)
    }
    private var composer: some View {
        VStack(spacing: 6) {
            if activeMentionRange != nil {
                mentionPicker
                    .transition(.opacity)
            }
            if speech.isRecording {
                Label("正在聆听…再次点击麦克风结束", systemImage: "waveform")
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassSurface(in: Capsule(), interactive: false)
            } else if let error = speech.errorText {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassSurface(in: Capsule(), interactive: false)
            }
            if !attachment.isEmpty { ComposerAttachmentChip(model: attachment) }
            if let replyToMessageID, let quoted = model.state.messages.first(where: { $0.id == replyToMessageID }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left").foregroundStyle(.secondary)
                    Text("回复：\(quoted.senderName ?? (quoted.role == .user ? "你" : "伙伴")) · \(quoted.content)")
                        .font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Button { self.replyToMessageID = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("取消回复")
                }.padding(.horizontal, 14)
            }
            GlassGroup(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    Menu {
                        Section("添加附件") {
                            Button { inputFocused = false; showPhotos = true } label: { Label("图片", systemImage: "photo") }
                            if CameraPicker.isAvailable {
                                Button { inputFocused = false; openCamera() } label: { Label("拍照", systemImage: "camera") }
                            }
                            Button { inputFocused = false; showFiles = true } label: { Label("文件", systemImage: "paperclip") }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium)).foregroundStyle(.primary)
                            .frame(width: Self.barHeight, height: Self.barHeight).contentShape(Circle())
                            .glassSurface(in: Circle())
                    }
                    .accessibilityLabel("添加附件")

                    HStack(alignment: .bottom, spacing: 4) {
                        ZStack(alignment: .leading) {
                            MentionTextEditor(text: $model.draft, mentions: $mentionTokens,
                                              selection: $draftSelection,
                                              isFocused: $inputFocused, isComposing: $isComposingMention,
                                              onSubmit: send)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if model.draft.isEmpty {
                                Text("发消息给群聊")
                                    .font(.body).foregroundStyle(.tertiary)
                                    .padding(.leading, 0).allowsHitTesting(false)
                            }
                        }
                        if model.canStop {
                            Button { Task { await model.stop() } } label: {
                                Image(systemName: "stop.circle.fill").font(.title3).foregroundStyle(.red)
                                    .frame(width: 36, height: Self.barHeight).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityLabel("停止讨论")
                            .disabled(model.confirmingStop)
                        } else if model.busy {
                            Button {} label: {
                                Image(systemName: "stop.circle.fill").font(.title3).foregroundStyle(.red)
                                    .frame(width: 36, height: Self.barHeight).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(true).opacity(0.4)
                            .accessibilityLabel("正在回复")
                        } else {
                            Button(action: toggleSpeech) {
                                Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic")
                                    .font(.title3).foregroundStyle(speech.isRecording ? Color.red : Color.secondary)
                                    .frame(width: 36, height: Self.barHeight).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(speech.isRecording ? "停止语音输入" : "语音输入")
                        }
                    }
                    .padding(.leading, 18).padding(.trailing, 8)
                    .frame(minHeight: Self.barHeight)
                    .glassSurface(in: RoundedRectangle(cornerRadius: Self.barHeight / 2, style: .continuous))
                }
            }
        }
        .padding(.horizontal).padding(.top, 4).padding(.bottom, 8)
        .animation(.easeOut(duration: 0.16), value: activeMentionRange != nil)
    }
    private static let barHeight: CGFloat = 48

    private var activeMentionRange: Range<String.Index>? {
        guard inputFocused, !isComposingMention, draftSelection.length == 0 else { return nil }
        return GroupMentionToken.activeRange(in: model.draft, selection: draftSelection, mentions: mentionTokens)
    }

    private var mentionQuery: String {
        guard let range = activeMentionRange else { return "" }
        return String(model.draft[model.draft.index(after: range.lowerBound)..<range.upperBound])
    }

    private var mentionPicker: some View {
        let query = mentionQuery
        let members = model.group.members.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let showsEveryone = query.isEmpty || "everyone".localizedCaseInsensitiveContains(query)
        let itemCount = (showsEveryone ? 1 : 0) + members.count
        let itemHeight: CGFloat = 50
        let pickerHeight = itemCount == 0
            ? itemHeight
            : min(254, CGFloat(itemCount) * itemHeight + CGFloat(itemCount - 1))

        return ScrollView(.vertical) {
            VStack(spacing: 0) {
                if showsEveryone {
                    mentionRow(title: "everyone", action: { insertMention(.everyone) })
                    if !members.isEmpty {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.leading, 62)
                    }
                }
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    mentionRow(member: member) { insertMention(.member(member)) }
                        .disabled(!member.available)
                    if index < members.count - 1 {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.leading, 62)
                    }
                }
                if !showsEveryone && members.isEmpty {
                    Text("没有匹配的群成员")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(height: pickerHeight) // Five rows occupy real layout space, including their touch targets.
        .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: false)
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func mentionRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                everyoneAvatar
                    .frame(width: 36, height: 36)
                    .allowsHitTesting(false)
                Text(title).font(.system(size: 17, weight: .medium)).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
    }

    private func mentionRow(member: ChatGroupMember, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                GroupMemberAvatar(member: member, size: 36)
                    .allowsHitTesting(false)
                Text(member.name).font(.system(size: 17, weight: .medium)).foregroundStyle(.primary)
                Spacer(minLength: 0)
                if !member.available {
                    Text("不可用").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
    }

    private var everyoneAvatar: some View {
        ZStack {
            RobotAvatarView(action: .idle, size: 17, color: .brandFill, ambient: false).offset(x: -6, y: 2)
            RobotAvatarView(action: .idle, size: 17, color: .brandAccent, ambient: false).offset(x: 6, y: 2)
            RobotAvatarView(action: .idle, size: 17, color: .primary, ambient: false).offset(y: -5)
        }
        .accessibilityHidden(true)
    }

    private func insertMention(_ target: GroupMentionTarget) {
        guard let range = activeMentionRange else { return }
        let name: String
        switch target {
        case .everyone: name = "everyone"
        case .member(let member):
            guard member.available, member.botID != nil else { return }
            name = member.name
        }
        let mentionText = "@\(name)"
        let insertion = mentionText + " "
        let replacementRange = NSRange(range, in: model.draft)
        let replacementEnd = NSMaxRange(replacementRange)
        let delta = (insertion as NSString).length - replacementRange.length
        mentionTokens = mentionTokens.compactMap { token in
            var updated = token
            let tokenEnd = NSMaxRange(token.range)
            if tokenEnd <= replacementRange.location { return updated }
            if token.range.location >= replacementEnd {
                updated.range.location += delta
                return updated
            }
            return nil
        }
        let mentionToken: GroupMentionToken
        switch target {
        case .everyone:
            mentionToken = GroupMentionToken(text: mentionText,
                                             range: NSRange(location: replacementRange.location, length: (mentionText as NSString).length),
                                             target: .everyone)
        case .member(let member):
            guard member.available, let botID = member.botID else { return }
            mentionToken = GroupMentionToken(text: mentionText,
                                             range: NSRange(location: replacementRange.location, length: (mentionText as NSString).length),
                                             target: .bot(id: botID))
        }
        mentionTokens.append(mentionToken)
        model.draft = (model.draft as NSString).replacingCharacters(in: replacementRange, with: insertion)
        draftSelection = NSRange(location: replacementRange.location + (insertion as NSString).length, length: 0)
        inputFocused = true
    }

    private func selectedRoute(for text: String) -> (memberIDs: [Int], everyone: Bool) {
        let source = text as NSString
        var memberIDs: [Int] = []
        var everyone = false
        for mention in mentionTokens where NSMaxRange(mention.range) <= source.length {
            guard source.substring(with: mention.range) == mention.text else { continue }
            switch mention.target {
            case .everyone:
                everyone = true
            case .bot(let botID):
                if let memberID = model.group.members.first(where: { $0.botID == botID })?.id { memberIDs.append(memberID) }
            }
        }
        return (memberIDs, everyone)
    }

    private var groupTitleButton: some View {
        Button { inputFocused = false; info = true } label: {
            HStack(spacing: 6) {
                GroupMemberAvatarStack(members: model.group.members.filter(\.available), size: 26, overlap: 9)
                Text(model.group.name).font(.headline).foregroundStyle(.primary).lineLimit(1).layoutPriority(1)
            }
        }
        .accessibilityLabel("\(model.group.name)，\(model.group.members.count) 位伙伴，查看群聊设置")
    }

    private func send() {
        guard !model.loading,!model.sending,!model.busy else { return }   // 回复进行中不能再发
        if model.hasUnconfirmedInput {model.recoverPendingSubmission();return}
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || attachment.ready != nil), text.count <= 2000, !attachment.blocksSend else { return }
        if speech.isRecording { speech.stop() }
        let selected = attachment.consume()
        let route = selectedRoute(for: model.draft)
        // The model retains the draft until the server accepts the turn.
        // Keep mention identities for a failed send, adjusting for trimming.
        let trimmedSource = text as NSString
        let leading = text.isEmpty ? 0 : (model.draft as NSString).range(of: text).location
        mentionTokens = mentionTokens.compactMap { $0.adjustedForTrimmedDraft(text, leading: leading) }
        draftSelection = NSRange(location: min(trimmedSource.length, max(0, draftSelection.location - leading)), length: 0)
        model.send(text: text, targetMemberIDs: route.memberIDs, everyone: route.everyone, replyToMessageID: replyToMessageID,
                   attachmentIDs: selected.map { [$0.id] } ?? [])
        inputFocused = true
    }

    private func openCamera() {
        Task {
            if await CameraPicker.requestAccess() { showCamera = true } else { cameraDenied = true }
        }
    }

    private func toggleSpeech() {
        if !speech.isRecording {
            inputFocused = false
            player.stop()
            speechBase = model.draft.isEmpty ? "" : model.draft + " "
        }
        Task { await speech.toggle(beforeRecording: { player.stop() }) }
    }

    @ViewBuilder private func bubble(_ message: GroupMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 50)
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(message.attachments) { AttachmentBubble(attachment: $0, api: app.api) }
                    if !message.content.isEmpty {
                        Text(message.content).textSelection(.enabled).padding(13)
                            .foregroundStyle(Color.userBubbleText).background(Color.userBubble, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }.contextMenu { Button("回复", systemImage: "arrowshape.turn.up.left") { replyToMessageID = message.id; inputFocused = true } }
        } else {
            HStack(alignment: .top, spacing: 10) {
                if let member = historicalMember(message) {
                    GroupMemberAvatar(member: member, size: 40,
                                      action: message.presentsIncompleteReply ? .warning
                                        : message.status == .streaming ? .replying : .idle)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.senderName ?? historicalMember(message)?.name ?? "伙伴").font(.caption).foregroundStyle(.secondary)
                    if message.retryOfMessageID != nil { Text("重试回应").font(.caption2).foregroundStyle(.secondary) }
                    let visibleText = displayContent(message)
                    if visibleText.isEmpty && message.status == .streaming { ProgressView("正在组织想法…") }
                    else { MessageContentView(text: visibleText).textSelection(.enabled) }
                    // 有可用正文时当正常回复；编排失败/停止不向用户露出「暂未完成」。
                    if message.presentsIncompleteReply {
                        Text(message.status == .failed ? "回应暂未完成" : message.status == .stopped ? "已停止 · 回应未完成" : "连接中断 · 回应未完成").font(.caption).foregroundStyle(.secondary)
                        Button("再试一次", systemImage: "arrow.clockwise") { model.retry(messageID: message.id) }
                            .font(.caption).disabled(!model.canRetry(messageID:message.id) || !(model.group.members.first { $0.id == message.memberID }?.available ?? false))
                    }
                }.padding(13).background(Color.botBubble, in: RoundedRectangle(cornerRadius: 18))
                Spacer(minLength: 20)
            }.contextMenu { Button("回复", systemImage: "arrowshape.turn.up.left") { replyToMessageID = message.id; inputFocused = true } }
        }
    }
    private func historicalMember(_ message: GroupMessage) -> ChatGroupMember? {
        if let snapshot = message.senderAppearance, let data = try? JSONEncoder().encode(snapshot), let member = try? JSONDecoder().decode(ChatGroupMember.self, from: data) { return member }
        return model.group.members.first { $0.id == message.memberID }
    }

    private func displayContent(_ message: GroupMessage) -> String {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.role == .bot, content.hasPrefix("{"), content.contains("\"source\""),
              let memberID = message.memberID, let data = content.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(GroupReplyEnvelope.self, from: data),
              envelope.source.role == "bot", envelope.source.memberID == memberID else {
            return message.content
        }
        return envelope.text
    }
}

private enum GroupMentionTarget {
    case everyone
    case member(ChatGroupMember)
}

private struct GroupNotificationFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

private struct GroupReplyEnvelope: Decodable {
    struct Source: Decodable {
        let role: String
        let memberID: Int
        enum CodingKeys: String, CodingKey { case role; case memberID = "member_id" }
    }
    let source: Source
    let text: String
}
