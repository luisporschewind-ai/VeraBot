import SwiftUI
import VeraBotCore

/// Bot 头像：相册照片优先；没有照片时用头像实验室的默认形象。
/// 对话页导航栏传入当前姿态并开启动画；首页列表等处保持静态空闲（默认参数）。
struct LiveBotAvatar: View {
    let botID: Int
    let emoji: String
    let color: String
    var hasAvatar: Bool = false
    var updatedAt: String?
    var size: CGFloat = 44
    var pose: AvatarLabState = .idle
    var animated = false

    @Environment(AppState.self) private var app

    var body: some View {
        let photo = app.avatars.image(forBot: botID)
        Group {
            switch BotAvatarDisplay(hasPhoto: photo != nil, storedAvatar: emoji) {
            case .photo:
                BotAvatar(emoji: emoji, color: color, image: photo, size: size)
            case .figure:
                // 静态形象只是装饰：列表行已经读 Bot 名称，不再读「方糖，空闲」
                DefaultBotFigure(storedAvatar: emoji, pose: pose, animated: animated, size: size)
                    .accessibilityHidden(!animated)
            }
        }
        .task(id: "\(botID)|\(hasAvatar)|\(updatedAt ?? "")") {
            await app.avatars.ensureBot(id: botID, hasAvatar: hasAvatar, updatedAt: updatedAt, api: app.api)
        }
    }
}
