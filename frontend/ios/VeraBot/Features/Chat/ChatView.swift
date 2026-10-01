import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct ChatView: View {
    @State private var vm: ChatViewModel
    @State private var speech = SpeechInput()
    @State private var input = ""
    @State private var speechBase = ""   // 开始录音前输入框已有的文字
    @FocusState private var focused: Bool
    @State private var showInfo = false         // Bot 详情页（清空对话 / Bot 设置已移入详情页）
    @State private var sendCount = 0            // 触感反馈触发器：每次发送 +1
    @Environment(AppState.self) private var app

    init(bot: Bot, api: any VeraBotAPI) {
        _vm = State(initialValue: ChatViewModel(bot: bot, api: api))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.items) { item in
                        MessageRow(item: item, bot: vm.bot)
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
            .background(Color(.systemGroupedBackground))
            .onChange(of: vm.scrollTick) {
                proxy.scrollTo("bottom", anchor: .bottom)   // 新消息 / 流式输出：滚到最后一条
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                // 只响应本页输入框的键盘；sheet（Bot 详情）里的键盘不应滚动对话页
                guard focused, !showInfo else { return }
                proxy.scrollTo("bottom", anchor: .bottom)   // 键盘弹出后：确保最后一条可见
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle("\(vm.bot.avatar) \(vm.bot.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 标题（头像 + 名称 + ›）可点击 → Bot 详情；右上角不再放按钮
            ToolbarItem(placement: .principal) {
                Button { focused = false; showInfo = true } label: {   // 弹出 sheet 前收起键盘
                    HStack(spacing: 6) {
                        LiveBotAvatar(botID: vm.bot.id, emoji: vm.bot.avatar, color: vm.bot.color,
                                       hasAvatar: vm.bot.hasAvatar, updatedAt: vm.bot.avatarUpdatedAt, size: 26)
                        Text(vm.bot.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(vm.bot.name)，查看 Bot 详情")
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
        .task { await vm.load() }
        .onDisappear { focused = false }   // 返回 / 离开页面时收起键盘
    }

    /// 底部输入栏：[＋ 附件] [输入框] [🎙] [发送]
    private var composer: some View {
        VStack(spacing: 4) {
            if speech.isRecording {
                Label("正在聆听…再次点击麦克风结束", systemImage: "waveform")
                    .font(.caption).foregroundStyle(.red)
            } else if let err = speech.errorText {
                Text(err).font(.caption).foregroundStyle(.orange)
            }
            HStack(alignment: .bottom, spacing: 8) {
                // 附件占位菜单（图片 / 相机 / 文件，均即将支持，暂不上传）
                Menu {
                    Section("添加附件") {
                        Button {} label: { Label("图片（即将支持）", systemImage: "photo") }.disabled(true)
                        Button {} label: { Label("相机（即将支持）", systemImage: "camera") }.disabled(true)
                        Button {} label: { Label("文件（即将支持）", systemImage: "paperclip") }.disabled(true)
                    }
                } label: {
                    Image(systemName: "plus").font(.title3.bold())
                        .frame(width: 38, height: 38)
                        .foregroundStyle(.white)
                        .background(Color.brand, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("添加附件")

                TextField("发消息…", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    if !speech.isRecording {
                        speechBase = input.isEmpty ? "" : input + " "
                    }
                    Task { await speech.toggle() }
                } label: {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.title3)
                        .frame(width: 38, height: 38)
                        .foregroundStyle(speech.isRecording ? .white : .primary)
                        .background(speech.isRecording ? Color.red : Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel(speech.isRecording ? "停止语音输入" : "语音输入")

                Button("发送") {
                    if speech.isRecording { speech.stop() }
                    let text = input
                    input = ""
                    focused = true   // 发送后键盘保持弹出，便于连续输入
                    sendCount += 1
                    Task { await vm.send(text) }
                }
                .buttonStyle(.borderedProminent)
                .frame(height: 38)
                .disabled(vm.sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: speech.transcript) {
            if speech.isRecording || !speech.transcript.isEmpty {
                input = speechBase + speech.transcript   // 实时写入部分识别结果，由用户确认后发送
            }
        }
        .onDisappear { speech.stop() }
        .hapticFeedback(.impact(weight: .light), trigger: sendCount)   // 发送消息（受「触感反馈」开关控制）
        .hapticFeedback(.selection, trigger: speech.isRecording)        // 开始 / 结束语音输入
    }
}
