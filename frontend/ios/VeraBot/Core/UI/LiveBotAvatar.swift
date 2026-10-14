import SwiftUI
import VeraBotCore

/// Bot 头像：相册照片优先；其余位置统一使用新版头像实验室的可动形象。
/// 对话页导航栏可传入执行状态；Bot 列表可开启持续的常态 Idle 动画。
struct LiveBotAvatar: View {
    let botID: Int
    let emoji: String
    let color: String
    var hasAvatar: Bool = false
    var updatedAt: String?
    var size: CGFloat = 44
    var action: BotAvatarState = .idle
    var animated = false
    var appearance: BotAppearance?

    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let photo = app.avatars.image(forBot: botID)
        let selectedColor = BotAvatarColorPalette.appearanceColor(for: color)
        let selectedAppearance = appearance.map { original in
            var updated = original
            if let selectedColor { updated.palette.body = selectedColor }
            return updated
        }
        Group {
            switch BotAvatarDisplay(hasPhoto: photo != nil, storedAvatar: emoji) {
            case .photo:
                BotAvatar(emoji: emoji, color: color, image: photo, size: size)
            case .figure:
                RobotAvatarView(action: action, size: size,
                                color: selectedColor?.swiftUIColor ?? Color(hex: color),
                                ambient: animated, appearance: selectedAppearance,
                                staticPreview: action == .warning || action == .failure || action == .error)
                    .accessibilityLabel("Bot，\(action.title)")
            }
        }
        .overlay(alignment: .topLeading) {
            if photo != nil, action != .idle { Image(systemName: action == .awaitingConfirmation ? "questionmark.circle.fill" : action == .success ? "checkmark.circle.fill" : action == .warning ? "exclamationmark.circle.fill" : "ellipsis.circle.fill").font(.caption).foregroundStyle(Color.accentColor, Color.appBackground).accessibilityLabel(action.title) }
        }
        .overlay(alignment:.bottomTrailing) {
            if app.primaryBotID == botID {
                Image(systemName:"star.circle.fill").font(.system(size:max(14,size*0.3))).foregroundStyle(Color.accentColor,Color.appBackground).accessibilityLabel("主 Bot")
            }
        }
        .task(id: "\(botID)|\(hasAvatar)|\(updatedAt ?? "")") {
            await app.avatars.ensureBot(id: botID, hasAvatar: hasAvatar, updatedAt: updatedAt, api: app.api)
        }
    }
}


extension ConversationActivity {
    var avatarAction: BotAvatarState {
        if state == "awaiting_user" || state == "awaiting_approval" { return .awaitingConfirmation }
        if ["failed", "interrupted", "stopped"].contains(state) { return .warning }
        switch phase { case "recalling": return .recalling; case "thinking", "retry_wait": return .thinking; case "tool": return .working; case "delegating": return .delegating; case "replying": return .replying; default: return .idle }
    }
}
