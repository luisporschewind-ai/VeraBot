import SwiftUI
import UIKit

/// Bot 头像：照片或表情都显示为正圆（表情放在 Bot 颜色的圆底上）。
struct BotAvatar: View {
    let emoji: String
    let color: String
    var image: UIImage? = nil
    var size: CGFloat = 44

    var body: some View {
        CircleAvatar(image: image, background: Color(hex: color), size: size) {
            Text(emoji)
                .font(.system(size: size * 0.55))
        }
    }
}
