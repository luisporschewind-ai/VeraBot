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

/// 首页导航栏里的头像：照片/首字略缩小，嵌在外层圆形玻璃底内，留出约 2.5pt 白环。
/// 外径由 `BotListView` 传入（iOS 26 为 44pt，与右侧搜索 / ＋ 等大；更早系统 30pt）。
struct HomeAvatarLabel: View {
    let name: String
    var image: UIImage?
    var size: CGFloat = 30
    /// 照片与玻璃外圆之间的白环宽度（单侧）。
    private static let ringWidth: CGFloat = 2.5

    var body: some View {
        UserAvatar(name: name, image: image, size: size - Self.ringWidth * 2)
            .frame(width: size, height: size)
    }
}

/// 与 `JumpToLatestButton` 同款圆形玻璃底：iOS 26 `.glassEffect`；旧系统 `.ultraThinMaterial`。
/// 首页左上头像与右侧搜索 / ＋ 同为抬起的白玻璃圆按钮观感。
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
