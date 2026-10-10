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
                                ambient: animated, appearance: selectedAppearance)
                    .accessibilityLabel("Bot，\(action.title)")
            }
        }
        .task(id: "\(botID)|\(hasAvatar)|\(updatedAt ?? "")") {
            await app.avatars.ensureBot(id: botID, hasAvatar: hasAvatar, updatedAt: updatedAt, api: app.api)
        }
    }
}
