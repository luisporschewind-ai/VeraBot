import SwiftUI
import VeraBotCore

/// 带照片的 Bot 头像：有自定义图时显示圆形照片，否则回退表情。图片来自共享的 AvatarStore。
struct LiveBotAvatar: View {
    let botID: Int
    let emoji: String
    let color: String
    var hasAvatar: Bool = false
    var updatedAt: String?
    var size: CGFloat = 44

    @Environment(AppState.self) private var app

    var body: some View {
        BotAvatar(emoji: emoji, color: color, image: app.avatars.image(forBot: botID), size: size)
            .task(id: "\(botID)|\(hasAvatar)|\(updatedAt ?? "")") {
                await app.avatars.ensureBot(id: botID, hasAvatar: hasAvatar, updatedAt: updatedAt, api: app.api)
            }
    }
}
