import SwiftUI
import UIKit

/// 用户头像：有自定义照片时显示圆形图片，否则是昵称首字 + 品牌色圆底。
struct UserAvatar: View {
    let name: String
    var image: UIImage? = nil
    var size: CGFloat = 32

    var body: some View {
        CircleAvatar(image: image, background: Color.brandFill, size: size) {
            Text(AvatarInitial.text(for: name))
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// 首页导航栏里的头像：正圆（照片或首字圆底）。外层由 `BotListView` 套圆形玻璃底。
/// iOS 26 关掉系统共享玻璃胶囊后用 44pt，与右侧圆形按钮等大；更早系统 30pt。
struct HomeAvatarLabel: View {
    let name: String
    var image: UIImage?
    var size: CGFloat = 30

    var body: some View {
        UserAvatar(name: name, image: image, size: size)
    }
}

/// iOS 26 用系统 `.glassEffect`；旧系统回退到 `.ultraThinMaterial` 圆形底（与 `JumpToLatestButton` 一致）。
struct HomeAvatarGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}
