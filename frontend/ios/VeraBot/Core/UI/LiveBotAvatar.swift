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
                // 列表 44pt：≈14pt（约 32%）。小头像去掉 14pt 下限，否则 title pill 26pt 上星标≈54% 盖住脸。
                let badge = min(max(14, size * 0.3), size * 0.38)
                Image(systemName: "star.circle.fill")
                    .font(.system(size: badge))
                    .foregroundStyle(Color.accentColor, Color.appBackground)
                    .offset(x: size < 40 ? size * 0.08 : 0, y: size < 40 ? size * 0.08 : 0)
                    .accessibilityLabel("主 Bot")
            }
        }
        .task(id: "\(botID)|\(hasAvatar)|\(updatedAt ?? "")") {
            await app.avatars.ensureBot(id: botID, hasAvatar: hasAvatar, updatedAt: updatedAt, api: app.api)
        }
    }
}


extension ConversationActivity {
    var avatarAction: BotAvatarState {
        if displayState == "awaiting_user" || displayState == "awaiting_approval" { return .awaitingConfirmation }
        if ["failed", "interrupted", "stopped"].contains(displayState) { return .warning }
        switch displayPhase { case "recalling": return .recalling; case "thinking", "retry_wait": return .thinking; case "tool": return .working; case "delegating": return .delegating; case "replying": return .replying; default: return .idle }
    }
}
