import SwiftUI
import UIKit

/// 用户头像：有自定义照片时显示圆形图片，否则是昵称首字 + 品牌色圆底。
struct UserAvatar: View {
    let name: String
    var image: UIImage? = nil
    var size: CGFloat = 32

    var body: some View {
        CircleAvatar(image: image, background: Color.brand, size: size) {
            Text(AvatarInitial.text(for: name))
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// 首页导航栏里的头像：正圆（照片或首字圆底）。iOS 26 关掉系统玻璃底后用 44pt，与右侧圆形按钮等大；更早系统 30pt。
struct HomeAvatarLabel: View {
    let name: String
    var image: UIImage?
    var size: CGFloat = 30

    var body: some View {
        UserAvatar(name: name, image: image, size: size)
    }
}
