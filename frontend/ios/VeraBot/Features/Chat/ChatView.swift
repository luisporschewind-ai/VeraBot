import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VeraBotCore
import VeraBotNetworking

struct ChatView: View {
    @State private var vm: ChatViewModel
    @State private var speech = SpeechInput()
    @State private var input = ""
    @State private var speechBase = ""   // 开始录音前输入框已有的文字
    @FocusState private var focused: Bool
    @State private var showInfo = false         // Bot 详情页（清空对话 / Bot 设置已移入详情页）
    @State private var showMemoryList = false
    @State private var sendCount = 0            // 触感反馈触发器：每次发送 +1
    @State private var attachment: ComposerAttachmentModel   // 待发送图片（最多 1 张）
    @State private var showPhotos = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var cameraDenied = false
    @Environment(AppState.self) private var app
    @Environment(BotTravelStore.self) private var travelStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.quickPromptsEnabled) private var quickPromptsEnabled = SettingsKeys.quickPromptsEnabledDefault
    let highlightMessageID: Int?
    @State private var travelTripToShow: BotTravelTrip?

    init(bot: Bot, api: any VeraBotAPI, highlightMessageID: Int? = nil) {
        self.highlightMessageID = highlightMessageID
        _vm = State(initialValue: ChatViewModel(bot: bot, api: api))
        _attachment = State(initialValue: ComposerAttachmentModel(botID: bot.id, api: api))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.items) { item in
                        MessageRow(item: item, bot: vm.bot, vm: vm)
                            .id(item.messageID.map { "m\($0)" } ?? item.id.uuidString)
                    }
                    ForEach(vm.memorySuggestions) { suggestion in
                        MemorySuggestionCard(suggestion: suggestion, vm: vm)
                    }
                    if let e = vm.errorText {
                        Text(e).font(.footnote).foregroundStyle(.red)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .bottomAnchoredScrolling()                    // 初次进入 & 键盘弹出时保持贴底（iOS 18+；17 由 keyboardDidShow 滚动兜底）
            .scrollDismissesKeyboard(.interactively)      // 下拉消息列表可交互式收起键盘
            .onTapGesture { focused = false }             // 点空白处收起键盘（气泡内按钮优先响应）
            .background(Color.appBackground)
            .onChange(of: vm.scrollTick) {
                if let mid = highlightMessageID, vm.items.contains(where: { $0.messageID == mid }) {
                    proxy.scrollTo("m\(mid)", anchor: .center)
                } else {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                // 只响应本页输入框的键盘；sheet（Bot 详情）里的键盘不应滚动对话页
                guard focused, !showInfo else { return }
                proxy.scrollTo("bottom", anchor: .bottom)   // 键盘弹出后：确保最后一条可见
            }
        }
        .bottomBar { composer }   // iOS 26 safeAreaBar：消息滚到输入栏下方有系统滚动边缘效果（同顶部导航栏）；旧系统 safeAreaInset
        .inAppBrowser()   // 消息里的 http/https 链接在 App 内 SFSafariViewController 打开；tel: / mailto: 交给系统
        .navigationTitle(vm.bot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 标题（头像 + 名称）可点击 → Bot 详情；右上角不再放按钮
            ToolbarItem(placement: .principal) {
                botTitleButton
                    .glassButtonStyle()   // iOS 26 Liquid Glass 胶囊；旧系统 bordered
                    .buttonBorderShape(.capsule)
            }
        }
        // Bot 详情：系统默认 sheet（page sheet 卡片，非 push / 非全屏），下滑关闭
        .sheet(isPresented: $showInfo, onDismiss: {
            vm.scrollTick += 1   // sheet 关闭后重新贴底（无动画），确保布局与滚动位置一致
        }) {
            NavigationStack {
                BotInfoView(vm: vm)
            }
            .environment(app)
        }
        .task {
            await vm.load()
            if quickPromptsEnabled { await vm.refreshQuickPrompts() }
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
        .hapticFeedback(.success, trigger: vm.memoryConfirmTick)   // 确认记住 / 忘掉（受「触感反馈」开关控制）
        .onDisappear { focused = false }   // 返回 / 离开页面时收起键盘
    }

    /// 先查相机权限：未决定时系统弹窗；已拒绝则提示前往设置
    private func openCamera() {
        Task {
            if await CameraPicker.requestAccess() { showCamera = true } else { cameraDenied = true }
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
        .onDisappear { speech.cancel() }
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

    /// 发送：键盘 return 键触发；空内容或上一条仍在回复时忽略（文字保留）。
    /// 有图时可以只发图片；图片处理 / 上传中或上传失败时不发送（输入栏上方显示状态）。
    private func send() {
        guard travelStore.activeTrip(botID: vm.bot.id) == nil else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vm.sending, !attachment.blocksSend else { return }
        guard !text.isEmpty || attachment.ready != nil else { return }
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
            speechBase = input.isEmpty ? "" : input + " "
        }
        Task { await speech.toggle() }
    }
}
