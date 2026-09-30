import Foundation
import SwiftUI

struct BotAvatar: View {
    let emoji: String
    let color: String
    var size: CGFloat = 44

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Color(hex: color), in: RoundedRectangle(cornerRadius: size * 0.33, style: .continuous))
    }
}
