import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VeraBotCore
import VeraBotNetworking
import VeraBotTTS
import VeraBotData

struct ChatView: View {
    @State private var notificationViewport: CGSize = .zero
    @State private var notificationFrames: [Int: CGRect] = [:]
    @State private var vm: ChatViewModel
    @State private var speech = SpeechInput()
    @State private var viewport: CGRect = .zero
    @State private var composerViewport: CGRect = .zero
    @State private var pageVisible = false
    @State private var browserCovered = false
    @State private var reading = ConversationReadingSession()
    @State private var entered = false
    @State private var initialPositionReady = false
    @State private var followsBottom = true
    @State private var bottomAnchor: CGRect = .zero   // 只在 updateFollowsBottom 里读，避免滚动时整页重算 body
    @State private var input = ""
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var speechBase = ""   // 开始录音前输入框已有的文字
    @FocusState private var focused: Bool
    @State private var showTasks = false
    @State private var showInfo = false         // Bot 详情页（清空对话 / Bot 设置已移入详情页）
    @State private var confirmClearConversation = false
    @State private var confirmDeleteBot = false
    @State private var deletingBot = false
    @State private var showMemoryList = false
    @State private var sendCount = 0            // 触感反馈触发器：每次发送 +1
    @State private var attachment: ComposerAttachmentModel   // 待发送图片（最多 1 张）
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var cameraDenied = false
    @Environment(AppState.self) private var app
    @Environment(SpeechPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(BotTravelStore.self) private var travelStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.quickPromptsEnabled) private var quickPromptsEnabled = SettingsKeys.quickPromptsEnabledDefault
    let highlightMessageID: Int?
    @State private var travelTripToShow: BotTravelTrip?

    init(bot: Bot, api: any VeraBotAPI, repository: ConversationRepository? = nil, highlightMessageID: Int? = nil) {
        self.highlightMessageID = highlightMessageID
        _vm = State(initialValue: ChatViewModel(bot: bot, api: api, repository: repository))
        _attachment = State(initialValue: ComposerAttachmentModel(botID: bot.id, api: api))
    }

    @ViewBuilder
    private func messageCell(_ item: ChatViewModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let id = item.messageID, id == reading.dividerMessageID {
                NewMessagesDivider()
            }
            MessageRow(item: item, bot: vm.bot, vm: vm)
                .conversationReadVisibility(viewport: effectiveViewport, enabled: canRead && !item.isUser, revision: item.publicationRevision) {
                    guard let id = item.messageID else { return }
                    await app.markVisible(kind: "private", id: vm.bot.id, generation: item.generation, message: MessagePublication(messageID: id, publicationRevision: item.publicationRevision))
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: ChatNotificationFrames.self,
                            value: item.messageID.map { [$0: geometry.frame(in: .named("notificationChatViewport"))] } ?? [:])
                    }
                }
        }
        .id(item.messageID.map { "m\($0)" } ?? item.id.uuidString)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if vm.hasOlderMessages {
                            Button(vm.loadingOlder ? "正在加载…" : "加载更早的消息") { Task { await vm.loadOlder() } }
                                .disabled(vm.loadingOlder).font(.footnote)
                        }
                        ForEach(vm.items) { item in
                            messageCell(item)
                        }
                        ForEach(vm.memorySuggestions) { suggestion in
                            MemorySuggestionCard(suggestion: suggestion, vm: vm)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .conversationBottomAnchor { bottomAnchor = $0; updateFollowsBottom() }
                }
                .padding()
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
            .onPreferenceChange(ChatNotificationFrames.self) { frames in
                notificationFrames = frames; updateNotificationVisibility()
            }
            .bottomAnchoredScrolling()                    // 初次进入 & 键盘弹出时保持贴底（iOS 18+；17 由 keyboardDidShow 滚动兜底）
            .scrollDismissesKeyboard(.interactively)      // 下拉消息列表可交互式收起键盘
            .onTapGesture { focused = false }             // 点空白处收起键盘（气泡内按钮优先响应）
            .background(Color.appBackground)
            .onChange(of: vm.scrollTick) {
                guard initialPositionReady else { return }
                if !entered && !vm.items.isEmpty {
                    if let target = highlightMessageID ?? reading.dividerMessageID, vm.items.contains(where: { $0.messageID == target }) { proxy.scrollTo("m\(target)", anchor: .center) }
                    else { proxy.scrollTo("bottom", anchor: .bottom) }
                    entered = true
                } else if followsBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                // 只响应本页输入框的键盘；sheet（Bot 详情）里的键盘不应滚动对话页
                guard focused, !showInfo, followsBottom else { return }
                proxy.scrollTo("bottom", anchor: .bottom)   // 键盘弹出后：确保最后一条可见
            }
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
        .bottomBar {
            VStack(spacing: 8) {
                if let notice = vm.notice {
                    PageConnectionNotice(notice: notice) { Task { await vm.load() } }
                        .padding(.horizontal, 16)
                }
                composer
            }
            .conversationComposer($composerViewport)
        }   // iOS 26 safeAreaBar：消息滚到输入栏下方有系统滚动边缘效果（同顶部导航栏）；旧系统 safeAreaInset
        .inAppBrowser(isPresented: $browserCovered)   // 消息里的 http/https 链接在 App 内 SFSafariViewController 打开；tel: / mailto: 交给系统
        .navigationTitle(vm.bot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 标题（头像 + 名称）可点击 → Bot 详情
            ToolbarItem(placement: .principal) {
                botTitleButton
                    .glassButtonStyle()   // iOS 26 Liquid Glass 胶囊；旧系统 bordered
                    .buttonBorderShape(.capsule)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("任务"){showTasks=true}
                    Button(role: .destructive) {
                        confirmClearConversation = true
                    } label: {
                        Label("清空对话", systemImage: "trash")
                    }
                    .disabled(vm.sending)

                    Button(role: .destructive) {
                        confirmDeleteBot = true
                    } label: {
                        Label("删除 Bot", systemImage: "person.crop.circle.badge.minus")
                    }
                    .disabled(deletingBot)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("更多")
            }
        }
        // Bot 详情：系统默认 sheet（page sheet 卡片，非 push / 非全屏），下滑关闭
        .sheet(isPresented: $showInfo, onDismiss: {
            // Preserve the reading position after dismissing Bot details.
        }) {
            NavigationStack {
                BotInfoView(vm: vm)
            }
            .environment(app)
        }
        .confirmationDialog("清空与「\(vm.bot.name)」的全部对话？", isPresented: $confirmClearConversation, titleVisibility: .visible) {
            Button("清空对话", role: .destructive) {
                Task { await vm.clear() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("对话内容和对话摘要将被删除，已确认的记忆会保留。此操作不可撤销。")
        }
        .confirmationDialog(BotDeletion.title(vm.bot.name), isPresented: $confirmDeleteBot, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task { await deleteBot() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(BotDeletion.message(vm.bot.name))
        }
        .sheet(isPresented:$showTasks){NavigationStack{TaskListView(botID:vm.bot.id,botName:vm.bot.name)}}
        .task {
            input = await vm.loadDraft()
            pageVisible = true; vm.activityRepository = app.activityRepository
            vm.preferredAddress = app.displayName
            await app.refreshActivityForEntry()
            if !entered { initialPositionReady = false; reading.enter(app.activity(kind: "private", id: vm.bot.id)?.unreadMessages ?? []) }
            await vm.load()
            if !entered, let target = highlightMessageID ?? reading.dividerMessageID { await vm.ensureMessageLoaded(target) }
            initialPositionReady = true; vm.scrollTick += 1
            await app.markConversationRead(kind: "private", id: vm.bot.id)
            if quickPromptsEnabled { await vm.refreshQuickPrompts() }
        }
        .onChange(of: notificationModalShown) { _, _ in updateNotificationVisibility() }
        .onChange(of: scenePhase) { _, _ in updateNotificationVisibility() }
        .onDisappear {
            if app.notificationEvents.visibleBotID == vm.bot.id {
                app.notificationEvents.visibleBotID = nil; app.notificationEvents.visibleMessageIDs = []
            }
        }
        .onChange(of: quickPromptsEnabled) { _, enabled in
            if enabled { Task { await vm.refreshQuickPrompts() } }
            else { vm.quickPrompts = [] }
        }
        .onChange(of: vm.openBotSettingsTick) { showInfo = true }
        // 只用系统相册选择器（PhotosPicker，单选；再选替换），不需要相册权限
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
        // 拍照：系统相机全屏（UIImagePickerController），拍到的图与相册选图走同一路径
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { attachment.pick($0) }.ignoresSafeArea()
        }
        .alert("无法使用相机", isPresented: $cameraDenied) {
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请在「设置」中允许 VeraBot 使用相机。")
        }
        .onChange(of: app.activity(kind: "private", id: vm.bot.id)?.revision) { _, _ in
            guard pageVisible else { return }
            let activity = app.activity(kind: "private", id: vm.bot.id)
            if let generation = activity?.generation, generation != vm.conversationGeneration { reading.leave() }
            reading.include(activity?.unreadMessages ?? [])
            if let generation = activity?.generation, generation != vm.conversationGeneration { Task { await vm.recoverExecution() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { vm.leave() } else if pageVisible {
                Task { await resumeFromBackground() }
            }
        }
        .onChange(of: app.sessionGeneration) { _, _ in pageVisible = false; reading.leave(); vm.leave() }
        .hapticFeedback(.success, trigger: vm.memoryConfirmTick)   // 确认记住 / 忘掉（受「触感反馈」开关控制）
        .onDisappear {
            pageVisible = false; vm.leave()
            if !hasTemporaryCover { endReadingSession() }
            focused = false
            // 全屏相机临时遮盖对话，仍属于当前对话；返回列表才结束朗读。
            if !showCamera { player.stop() }
        }
    }

    private var effectiveViewport: CGRect {
        guard !composerViewport.isEmpty else { return viewport }
        return CGRect(x: viewport.minX, y: viewport.minY, width: viewport.width, height: max(0, min(viewport.maxY, composerViewport.minY) - viewport.minY))
    }
    private func updateFollowsBottom() {
        let next = ScrollBottomDetector.followsBottom(anchor: bottomAnchor, viewport: effectiveViewport, current: followsBottom)
        if next != followsBottom { followsBottom = next }
    }
    private var hasTemporaryCover: Bool { showInfo || showTasks || showMemoryList || showPhotos || showFiles || showCamera || cameraDenied || browserCovered || travelTripToShow != nil || confirmClearConversation || confirmDeleteBot }
    private var canRead: Bool { pageVisible && scenePhase == .active && app.selectedTab == 0 && !hasTemporaryCover }

    /// 先查相机权限：未决定时系统弹窗；已拒绝则提示前往设置
    private func openCamera() {
        Task {
            if await CameraPicker.requestAccess() { showCamera = true } else { cameraDenied = true }
        }
    }

    private func deleteBot() async {
        guard !deletingBot else { return }
        deletingBot = true
        defer { deletingBot = false }
        vm.notice = nil
        do {
            _ = try await app.api.deleteBot(vm.bot.id)
            dismiss()
        } catch {
            vm.notice = .fromAction(error, message: app.message(for: error))
        }
    }

    private var botTitleButton: some View {
        let action = BotAvatarState(vm.executionState)
        return Button { focused = false; showInfo = true } label: {   // 弹出 sheet 前收起键盘
            HStack(spacing: 6) {
                LiveBotAvatar(botID: vm.bot.id, emoji: vm.bot.avatar, color: vm.bot.color,
                               hasAvatar: vm.bot.hasAvatar, updatedAt: vm.bot.avatarUpdatedAt,
                               size: 26, action: action, animated: true,
                               appearance: vm.bot.supportedAppearance)
                Text(vm.bot.name).font(.headline).foregroundStyle(.primary).lineLimit(1).layoutPriority(1)
            }
        }
        .accessibilityLabel("\(vm.bot.name)，\(action.title)，查看 Bot 详情")
    }

    private var notificationModalShown: Bool {
        showInfo || showTasks || showMemoryList || showPhotos || showCamera || showFiles || travelTripToShow != nil
    }
    private func updateNotificationVisibility() {
        app.notificationEvents.visibleBotID = vm.bot.id
        app.notificationEvents.visibleGroupID = nil
        guard scenePhase == .active, !notificationModalShown else { app.notificationEvents.visibleMessageIDs = []; return }
        let viewport = CGRect(origin: .zero, size: notificationViewport)
        app.notificationEvents.visibleMessageIDs = Set(notificationFrames.filter { $0.value.intersects(viewport) }.keys)
    }

    /// 底部浮动输入栏（Liquid Glass）：[＋ 圆形玻璃按钮] [胶囊玻璃：输入框 … 🎙]。
    /// 无发送按钮：键盘 return 键（submitLabel .send）发送；无不透明底栏，消息从下方滚过；
    /// 用 Theme 的 bottomBar（iOS 26 safeAreaBar，系统底部滚动边缘效果 Scroll edge effect；旧系统 safeAreaInset）保证最后一条可见、随键盘上移。
    @ViewBuilder
    private var composer: some View {
        if let trip = travelStore.activeTrip(botID: vm.bot.id) {
            HStack(spacing: 12) {
                Image(systemName: "airplane")
                    .font(.title3).foregroundStyle(Color.brand)
                    .frame(width: 42, height: 42)
                    .background(Color.brandSoft, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(vm.bot.name)正在旅行")
                        .font(.subheadline.weight(.semibold))
                    Text("它会在旅程节点回来分享发现。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("看旅程") { travelTripToShow = trip }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(12)
            .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .sheet(item: $travelTripToShow) { trip in
                NavigationStack { BotTravelJourneyView(trip: trip) }
                    .environment(app)
                    .environment(travelStore)
            }
        } else {
            regularComposer
        }
    }

    private var regularComposer: some View {
        VStack(spacing: 6) {
            // 排队 / 生成中不再显示状态行（由输入栏右侧的停止按钮表示）；只保留需要用户处理的等待状态。
            ForEach(vm.replyTasks.filter { $0.state == "awaiting_user" || $0.state == "awaiting_approval" }) { task in
                HStack {
                    Text(task.state == "awaiting_user" ? "等你补充" : "待你确认").font(.caption)
                    if task.state == "awaiting_user" { Button(vm.selectedWaitTaskID == task.id ? "退出关联" : "回复此问题") { vm.selectedWaitTaskID = vm.selectedWaitTaskID == task.id ? nil : task.id }.font(.caption) }
                    Spacer()
                    Button("停止") { Task { await vm.stop(task) } }.font(.caption).disabled(vm.controlBusy.contains(task.id))
                }
            }
            if let userID = app.userID,
               vm.candidateMemoryCount > 0,
               input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !focused,
               UserDefaults.standard.string(forKey: candidateNudgeKey(userID)) != todayStamp {
                Button { showMemoryList = true } label: {
                    Label("有 \(vm.candidateMemoryCount) 条记忆待确认 · 查看", systemImage: "brain")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassSurface(in: Capsule())
                }
                .buttonStyle(.plain)
                .onAppear { UserDefaults.standard.set(todayStamp, forKey: candidateNudgeKey(userID)) }
            }
            if speech.isRecording {
                Label("正在聆听…再次点击麦克风结束", systemImage: "waveform")
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassSurface(in: Capsule(), interactive: false)
            } else if let err = speech.errorText {
                Text(err).font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassSurface(in: Capsule(), interactive: false)
            }
            if !attachment.isEmpty {
                ComposerAttachmentChip(model: attachment)
            }
            if quickPromptsEnabled && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !focused && !vm.quickPrompts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.quickPrompts, id: \.self) { prompt in
                            Button {
                                input = prompt
                                focused = true
                            } label: {
                                Text(prompt).lineLimit(1)
                                    .font(.caption)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .glassSurface(in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("填入快捷提问：\(prompt)")
                        }
                    }
                }
            }
            GlassGroup(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    // 附件菜单保持原有图片 / 拍照入口；文件由系统文件选择器提供
                    Menu {
                        Section("添加附件") {
                            Button { focused = false; showPhotos = true } label: { Label("图片", systemImage: "photo") }
                            if CameraPicker.isAvailable {
                                Button { focused = false; openCamera() } label: { Label("拍照", systemImage: "camera") }
                            }
                            Button { focused = false; showFiles = true } label: { Label("文件", systemImage: "paperclip") }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(width: Self.barHeight, height: Self.barHeight)
                            .contentShape(Circle())
                            .glassSurface(in: Circle())
                    }
                    .accessibilityLabel("添加附件")

                    HStack(alignment: .bottom, spacing: 4) {
                        TextField("向 \(vm.bot.name) 提问", text: $input, axis: .vertical)
                            .lineLimit(1...5)
                            .focused($focused)
                            .submitLabel(.send)
                            .onSubmit(send)
                            .padding(.vertical, 13)
                        if let task = vm.replyInProgress {
                            // 回复进行中只显示停止按钮，点按停止本次回复；完成 / 失败后恢复麦克风
                            Button { Task { await vm.stop(task) } } label: {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.red)
                                    .frame(width: 36, height: Self.barHeight)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(vm.controlBusy.contains(task.id))
                            .accessibilityLabel("停止回复")
                        } else {
                        Button(action: toggleSpeech) {
                            Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic")
                                .font(.title3)
                                .foregroundStyle(speech.isRecording ? Color.red : Color.secondary)
                                .frame(width: 36, height: Self.barHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(speech.isRecording ? "停止语音输入" : "语音输入")
                        }
                    }
                    .padding(.leading, 18).padding(.trailing, 8)
                    .frame(minHeight: Self.barHeight)
                    // 单行时为胶囊（圆角 = 高度一半），多行时保持同样圆角向上长高
                    .glassSurface(in: RoundedRectangle(cornerRadius: Self.barHeight / 2, style: .continuous))
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .onChange(of: input) { old, new in
            draftSaveTask?.cancel()
            draftSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await vm.saveDraft(new)
            }
            // 多行输入框（axis: .vertical）里 return 会插入换行：把「只多了一个换行」视为按下发送键，
            // 恢复原文并发送；粘贴的多行文本（一次多于一个字符）保留换行
            if new.count == old.count + 1,
               new.filter({ $0 == "\n" }).count == old.filter({ $0 == "\n" }).count + 1 {
                input = old
                send()
            }
        }
        .onChange(of: speech.transcript) {
            if speech.isRecording || !speech.transcript.isEmpty {
                input = speechBase + speech.transcript   // 实时写入部分识别结果，由用户确认后发送
            }
        }
        .onDisappear {
            draftSaveTask?.cancel()
            Task { await vm.saveDraft(input) }
            speech.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { speech.cancel() }   // 进入后台立即释放麦克风 / 音频会话
        }
        .hapticFeedback(.impact(weight: .light), trigger: sendCount)   // 发送消息（受「触感反馈」开关控制）
        .hapticFeedback(.selection, trigger: speech.isRecording)        // 开始 / 结束语音输入
        .sheet(isPresented: $showMemoryList) {
            NavigationStack {
                MemoryListView(botFilter: vm.bot)
            }
            .environment(app)
        }
    }

    private var todayStamp: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func candidateNudgeKey(_ userID: Int) -> String {
        "vb_memory_candidates_nudge.\(userID)"
    }

    private static let barHeight: CGFloat = 48

    /// 发送：键盘 return 键触发；只在提交中暂缓，后续独立消息由服务端排队。
    /// 有图时可以只发图片；图片处理 / 上传中或上传失败时不发送（输入栏上方显示状态）。
    /// 离开对话：清掉本次阅读状态，并把期间到达的回复一并标为已读。
    private func endReadingSession() {
        reading.leave(); entered = false
        let botID = vm.bot.id
        Task { await app.markConversationRead(kind: "private", id: botID) }
    }
    /// 从后台回到前台：刷新未读、为期间到达的回复标一次「新」分隔线，随后标为已读。
    private func resumeFromBackground() async {
        await app.refreshActivityForEntry()
        reading.resume(app.activity(kind: "private", id: vm.bot.id)?.unreadMessages ?? [])
        await app.markConversationRead(kind: "private", id: vm.bot.id)
        await vm.recoverExecution()
    }

    private func send() {
        guard travelStore.activeTrip(botID: vm.bot.id) == nil else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vm.sending, vm.replyInProgress == nil, !attachment.blocksSend else { return }
        guard !text.isEmpty || attachment.ready != nil else { return }
        if vm.selectedWaitTaskID != nil && attachment.ready != nil { vm.notice = .sentence("请先退出问题关联，再发送附件。"); return }
        if speech.isRecording { speech.stop() }
        let image = attachment.consume()
        input = ""
        focused = true   // 发送后键盘保持弹出，便于连续输入
        sendCount += 1
        Task {
            await vm.send(text, attachment: image)
            if quickPromptsEnabled { await vm.refreshQuickPrompts() }
        }
    }

    private func toggleSpeech() {
        if !speech.isRecording {
            player.stop()
            speechBase = input.isEmpty ? "" : input + " "
        }
        // 权限弹窗可能等待很久，真正开启麦克风前再次停止朗读。
        Task { await speech.toggle(beforeRecording: { player.stop() }) }
    }
}

private struct ChatNotificationFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
