import SwiftUI
import UIKit

struct BotAvatar: View {
    let emoji: String
    let color: String
    var image: UIImage? = nil
    var size: CGFloat = 44

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Text(emoji)
                .font(.system(size: size * 0.55))
                .frame(width: size, height: size)
                .background(Color(hex: color), in: RoundedRectangle(cornerRadius: size * 0.33, style: .continuous))
        }
    }
}
