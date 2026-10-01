import SwiftUI
import VeraBotCore

struct MessageRow: View {
    let item: ChatViewModel.Item
    let bot: Bot
    @AppStorage(SettingsKeys.ttsEnabled) private var ttsEnabled = true

    var body: some View {
        if item.isUser {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(item.text)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Color.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    ForEach(item.traces) { TraceView(trace: $0, fromBot: bot.name) }
                    if !item.text.isEmpty || item.streaming {
                        MessageContentView(text: item.text + (item.streaming ? " ▍" : ""))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.botBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .contextMenu { MessageCopyMenu(text: item.text) }   // 长按：复制 / 复制链接
                    }
                    if ttsEnabled && !item.streaming && !item.text.isEmpty {
                        SpeakButton(key: item.id.uuidString, text: item.text)
                    }
                }
                Spacer(minLength: 24)
            }
        }
    }
}
