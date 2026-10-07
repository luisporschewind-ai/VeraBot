import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct MemorySuggestionCard: View {
    let suggestion: MemorySuggestion
    let vm: ChatViewModel

    private var kindTitle: String {
        switch suggestion.kind {
        case .routineReminder: return "规律提醒建议"
        case .delegation: return "委派权限建议"
        case .unknown: return "建议"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(kindTitle, systemImage: suggestion.kind == .delegation ? "arrow.triangle.branch" : "calendar")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(suggestion.title).font(.subheadline).foregroundStyle(.primary)
            HStack(spacing: 8) {
                Button("接受") { Task { await vm.acceptMemorySuggestion(suggestion.id) } }
                    .prominentButtonStyle()
                Button("暂不") { Task { await vm.dismissMemorySuggestion(suggestion.id) } }
                    .glassButtonStyle()
                if vm.suggestionBusy.contains(suggestion.id) { ProgressView() }
            }
            .controlSize(.small)
            .disabled(vm.suggestionBusy.contains(suggestion.id))
            if let message = vm.suggestionErrors[suggestion.id] {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
        .accessibilityElement(children: .contain)
    }
}

struct MessageRow: View {
    @Environment(AppState.self) private var app
    let item: ChatViewModel.Item
    let bot: Bot
    let vm: ChatViewModel
    @AppStorage(SettingsKeys.ttsEnabled) private var ttsEnabled = true
    @State private var confirmDelete = false
    @State private var feedbackReason = false
    @State private var showMemoryReferences=false

    /// 只有已落库（有 messageID）且不在流式输出中的消息可删除；欢迎语、正在生成的回复不显示「删除」
    private var canDelete: Bool { item.messageID != nil && !item.streaming }

    var body: some View {
        content
            .confirmationDialog("删除这条消息？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { Task { await vm.delete(item) } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只删除这一条，已记住的内容不受影响。")
            }
            .sheet(isPresented:$showMemoryReferences) {
                NavigationStack { if let id=item.messageID { MemoryReferencesView(messageID:id).environment(app) } }
            }
    }

    /// 长按菜单：复制 / 复制链接（有正文时）+ 删除（系统 destructive 样式，点按后用系统确认框二次确认）
    @ViewBuilder private var messageMenu: some View {
        if !item.text.isEmpty {
            MessageCopyMenu(text: item.text)
        }
        if canDelete {
            Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") }
        }
        if !item.isUser,let id=item.messageID,!item.streaming {
            Button { showMemoryReferences=true } label:{Label("这条回答参考了哪些记忆",systemImage:"brain")}
                .disabled(id<=0)
        }
    }

    @ViewBuilder private var content: some View {
        if item.isUser {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(item.attachments) { attachment in
                        AttachmentBubble(attachment: attachment, api: vm.api)
                    }
                    if !item.text.isEmpty || item.attachments.isEmpty {
                        Text(item.text)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .foregroundStyle(Color.userBubbleText)
                            .background(Color.userBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if ttsEnabled && !item.text.isEmpty {
                        SpeakButton(key: item.id.uuidString, text: item.text)
                    }
                }
                // 长按整条用户消息（图片 + 文字）：复制 / 复制链接（有文字时）/ 删除；只有图片的消息也能删除
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu { messageMenu }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                               hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt, size: 34)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.traces) { trace in
                        // 记忆工具：待确认 → 确认卡片；其他结果 → 一行说明；执行中 / 非记忆工具 → 普通 Trace
                        if let p = trace.memoryProposal {
                            if p.isCard {
                                MemoryProposalCard(proposal: p, botName: bot.name, vm: vm)
                            } else {
                                MemoryToolNote(proposal: p)
                            }
                        } else if let pending = trace.pendingConfirmation {
                            ToolConfirmationCard(
                                action: vm.actionStates[pending.actionId] ?? pending.asPending(),
                                vm: vm
                            )
                        } else {
                            TraceView(trace: trace, fromBot: bot.name)
                        }
                    }
                    if !item.text.isEmpty || item.streaming {
                        // 朗读按钮放在气泡右下角：内层 VStack 宽度跟随气泡，按钮与气泡右边缘对齐
                        VStack(alignment: .trailing, spacing: 6) {
                            // 不再追加「▍」光标字符：首个 token 到达前气泡里只有它，显示成回复开头的一根黑色竖条。
                            // 等待首个 token 时用系统 ProgressView；之后正文逐字出现即可表示正在生成。
                            Group {
                                if item.text.isEmpty {
                                    ProgressView().accessibilityLabel("正在回复")
                                } else {
                                    MessageContentView(text: item.text)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.botBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            if !item.streaming && (item.messageID != nil || (ttsEnabled && !item.text.isEmpty)) {
                                HStack(spacing: 0) {
                                    if ttsEnabled && !item.text.isEmpty {
                                        SpeakButton(key: item.id.uuidString, text: item.text)
                                    }
                                    if item.messageID != nil {
                                        feedbackButtons
                                    }
                                }
                            }
                        }
                    }
                }
                // 长按整条回复（气泡与工具卡片）：复制 / 复制链接 / 删除；只有工具卡片、没有正文的回复也能删除。
                // 卡片里的按钮（记忆确认等）点按照常响应。
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu { messageMenu }
                Spacer(minLength: 24)
            }
            .confirmationDialog("哪里不满意？", isPresented: $feedbackReason, titleVisibility: .visible) {
                Button("太长") { Task { await vm.setFeedback(messageID: item.messageID ?? 0, rating: -1, reason: "too_long") } }
                Button("太短") { Task { await vm.setFeedback(messageID: item.messageID ?? 0, rating: -1, reason: "too_short") } }
                Button("不准确") { Task { await vm.setFeedback(messageID: item.messageID ?? 0, rating: -1, reason: "inaccurate") } }
                Button("语气") { Task { await vm.setFeedback(messageID: item.messageID ?? 0, rating: -1, reason: "tone") } }
                Button("其他") { Task { await vm.setFeedback(messageID: item.messageID ?? 0, rating: -1, reason: "other") } }
                Button("取消", role: .cancel) {}
            }
        }
    }

    /// 气泡下方、朗读按钮旁的 👍 / 👎。选中用填充图标；再点一次撤销。👎 先选原因。
    private var feedbackButtons: some View {
        let selected = item.feedback?.rating
        let busy = item.messageID.map { vm.feedbackBusy.contains($0) } ?? false
        return HStack(spacing: 0) {
        Button {
            guard let id = item.messageID, !busy else { return }
            if selected == 1 {
                Task { await vm.clearFeedback(messageID: id) }
            } else {
                Task { await vm.setFeedback(messageID: id, rating: 1, reason: nil) }
            }
        } label: {
            Image(systemName: selected == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.footnote)
                .foregroundStyle(selected == 1 ? Color.brand : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("有用")
        .accessibilityAddTraits(selected == 1 ? .isSelected : [])

        Button {
            guard let id = item.messageID, !busy else { return }
            if selected == -1 {
                Task { await vm.clearFeedback(messageID: id) }
            } else {
                feedbackReason = true
            }
        } label: {
            Image(systemName: selected == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                .font(.footnote)
                .foregroundStyle(selected == -1 ? Color.brand : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("没用")
        .accessibilityAddTraits(selected == -1 ? .isSelected : [])
        }
    }
}
