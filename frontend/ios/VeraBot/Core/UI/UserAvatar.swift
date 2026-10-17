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

/// 首页导航栏头像尺寸：对齐 iOS 26 右侧 ＋ 玻璃圆钮（模拟器 3x 实测 132px = 44pt，距右缘 16pt）。
enum HomeAvatarMetrics {
    static let toolbarGlassDiameter: CGFloat = 44
    /// 隐藏共享玻璃底后头像默认距左缘 20pt，左移 4pt 使其与 ＋ 距右缘的 16pt 对称。
    static let leadingCorrection: CGFloat = -4
    /// 照片与玻璃外圆之间的白环宽度（单侧）。
    static let ringWidth: CGFloat = 2.5
}

/// 首页导航栏里的头像：照片/首字略缩小，嵌在外层圆形玻璃底内，留出约 2.5pt 白环。
/// 外径由 `BotListView` 传入（iOS 26 为 `HomeAvatarMetrics.toolbarGlassDiameter`，与右侧 ＋ 等大；更早系统 30pt）。
struct HomeAvatarLabel: View {
    let name: String
    var image: UIImage?
    var size: CGFloat = 30

    var body: some View {
        UserAvatar(name: name, image: image, size: size - HomeAvatarMetrics.ringWidth * 2)
            .frame(width: size, height: size)
    }
}

/// 与 `JumpToLatestButton` 同款圆形玻璃底：iOS 26 `.glassEffect`；旧系统 `.ultraThinMaterial`。
/// 首页左上头像与右侧搜索 / ＋ 同为抬起的白玻璃圆按钮观感；尺寸由外层 frame 对齐系统工具栏指标。
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
