import SwiftUI
import VeraBotCore

struct MessageRow: View {
    let item: ChatViewModel.Item
    let bot: Bot
    let vm: ChatViewModel
    @AppStorage(SettingsKeys.ttsEnabled) private var ttsEnabled = true
    @State private var confirmDelete = false

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
    }

    /// 长按菜单：复制 / 复制链接（有正文时）+ 删除（系统 destructive 样式，点按后用系统确认框二次确认）
    @ViewBuilder private var messageMenu: some View {
        if !item.text.isEmpty {
            MessageCopyMenu(text: item.text)
        }
        if canDelete {
            Button(role: .destructive) { confirmDelete = true } label: { Label("删除", systemImage: "trash") }
        }
    }

    @ViewBuilder private var content: some View {
        if item.isUser {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(item.text)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(Color.userBubbleText)
                        .background(Color.userBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contextMenu { messageMenu }   // 长按：复制 / 复制链接 / 删除
                    if ttsEnabled && !item.text.isEmpty {
                        SpeakButton(key: item.id.uuidString, text: item.text)
                    }
                }
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
                        } else {
                            TraceView(trace: trace, fromBot: bot.name)
                        }
                    }
                    if !item.text.isEmpty || item.streaming {
                        MessageContentView(text: item.text + (item.streaming ? " ▍" : ""))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.botBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    if ttsEnabled && !item.streaming && !item.text.isEmpty {
                        SpeakButton(key: item.id.uuidString, text: item.text)
                    }
                }
                // 长按整条回复（气泡与工具卡片）：复制 / 复制链接 / 删除；只有工具卡片、没有正文的回复也能删除。
                // 卡片里的按钮（记忆确认等）点按照常响应。
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu { messageMenu }
                Spacer(minLength: 24)
            }
        }
    }
}
