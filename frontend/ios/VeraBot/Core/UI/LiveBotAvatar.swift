import SwiftUI
import VeraBotCore

/// Bot 头像：相册照片优先；其余位置统一使用新版头像实验室的可动形象。
/// 对话页导航栏传入执行状态并开启动画；列表等处使用静态空闲形象。
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
        Group {
            switch BotAvatarDisplay(hasPhoto: photo != nil, storedAvatar: emoji) {
            case .photo:
                BotAvatar(emoji: emoji, color: color, image: photo, size: size)
            case .figure:
                RobotAvatarView(action: action, size: size, color: Color(hex: color),
                                ambient: animated, appearance: appearance)
                    .accessibilityLabel("Bot，\(action.title)")
            }
        }
        .task(id: "\(botID)|\(hasAvatar)|\(updatedAt ?? "")") {
            await app.avatars.ensureBot(id: botID, hasAvatar: hasAvatar, updatedAt: updatedAt, api: app.api)
        }
    }
}
