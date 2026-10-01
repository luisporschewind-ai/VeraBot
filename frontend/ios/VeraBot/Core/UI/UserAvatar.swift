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

/// 首页导航栏里的头像：固定 30×30 正圆（照片或首字圆底），放在系统圆形玻璃按钮里。
struct HomeAvatarLabel: View {
    let name: String
    var image: UIImage?

    var body: some View {
        UserAvatar(name: name, image: image, size: 30)
    }
}
