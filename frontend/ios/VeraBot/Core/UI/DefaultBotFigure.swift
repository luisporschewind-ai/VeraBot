import SwiftUI
import VeraBotCore

/// 无相册照片时的默认新版机器人形象。
struct DefaultBotFigure: View {
    let storedAvatar: String
    var action: BotAvatarState = .idle
    var animated = false
    var size: CGFloat = 44
    var appearance: BotAppearance?
    var color: Color = RobotAvatarTone.graphite.color

    var body: some View {
        RobotAvatarView(action: action, size: size, color: color,
                        ambient: animated, appearance: appearance)
            .accessibilityLabel("Bot，\(action.title)")
    }
}
