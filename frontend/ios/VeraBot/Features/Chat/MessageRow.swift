import SwiftUI
import VeraBotCore

struct MessageRow: View {
    let item: ChatViewModel.Item
    let bot: Bot
    @AppStorage(SettingsKeys.ttsEnabled) private var ttsEnabled = true
    @Environment(AppState.self) private var app

    var body: some View {
        if item.isUser {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    if !app.displayName.isEmpty {
                        Text(app.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                        Text(markdown(item.text + (item.streaming ? " ▍" : "")))
                            .textSelection(.enabled)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.botBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

func markdown(_ s: String) -> AttributedString {
    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    // BUG-01：「15~21°C」这类区间里的 ~ 会被解析为删除线（strikethrough）；转义后按原文显示
    let escaped = s.replacingOccurrences(of: "~", with: "\\~")
    return (try? AttributedString(markdown: escaped, options: opts)) ?? AttributedString(s)
}
