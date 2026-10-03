import SwiftUI
import UIKit

struct AvatarLabCharacterView: View {
    let kind: AvatarLabCharacterKind
    let state: AvatarLabState
    let size: CGFloat
    var animated = true
    var replayID = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// 只在滚动视图里可见、且 App 在前台时循环。普通 ScrollView 滚出屏幕不会走 onDisappear。
    @State private var isVisible = false
    @State private var scrollVisibilityKnown = false

    /// 单次动作的触发键：状态切换或点「重播」都会重新播放一次。
    private struct OneShotKey: Equatable {
        let replay: Int
        let state: AvatarLabState
    }

    /// 读屏文字：「角色，状态」。
    static func accessibilityText(kind: AvatarLabCharacterKind, state: AvatarLabState) -> String {
        "\(kind.title)，\(state.title)"
    }

    /// 角标符号边长。68pt 时旧字号 `side * 0.13` 约 8.8pt，符号还有内边距，看起来过小。
    /// 改为按角标直径的 70% 铺满：68pt → 约 12.4pt（角标直径约 17.7pt）。
    static func badgeGlyphSide(_ side: CGFloat) -> CGFloat {
        side * 0.26 * 0.70
    }

    var body: some View {
        Group {
            if !animated || reduceMotion {
                art   // 减弱动态效果：只保留静态表情
            } else if state.isContinuous {
                if isVisible && scenePhase == .active {
                    // 持续状态（思考 / 执行 / 委派 / 回复）：系统 phaseAnimator 无 trigger 时循环播放
                    art.phaseAnimator([false, true]) { content, phase in
                        moving(content, phase: phase)
                    } animation: { _ in
                        .easeInOut(duration: state.motionDuration / 2)
                    }
                } else {
                    art
                }
            } else {
                art.phaseAnimator([false, true], trigger: OneShotKey(replay: replayID, state: state)) { content, phase in
                    moving(content, phase: phase)
                } animation: { _ in
                    .spring(response: state.motionDuration, dampingFraction: 0.58)
                }
            }
        }
        .modifier(AvatarScrollVisibility(enabled: animated, isVisible: $isVisible, scrollVisibilityKnown: $scrollVisibilityKnown))
        .onAppear {
            if animated, !scrollVisibilityKnown { isVisible = true }
        }
        .onDisappear {
            isVisible = false
            scrollVisibilityKnown = false
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(kind: kind, state: state))
    }

    private var art: some View {
        Group {
            if kind == .cloud {
                cloudArt
            } else {
                generatedArt
            }
        }
    }

    private var cloudArt: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let width = side * 0.80
            let height = width / AvatarLabCloudSilhouette.aspectRatio

            ZStack {
                Circle().fill(kind.backdropColor)
                LinearGradient(
                    colors: [kind.bodyColor.opacity(0.82), kind.bodyColor, kind.accentColor.opacity(0.60)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay {
                    // Broad, diffuse light rounds the cloud puffs without changing the source silhouette.
                    RadialGradient(
                        colors: [.white.opacity(0.66), .white.opacity(0)],
                        center: UnitPoint(x: 0.46, y: 0.23),
                        startRadius: 0, endRadius: width * 0.44
                    )
                }
                .overlay {
                    RadialGradient(
                        colors: [.white.opacity(0.36), .white.opacity(0)],
                        center: UnitPoint(x: 0.18, y: 0.46),
                        startRadius: 0, endRadius: width * 0.26
                    )
                }
                .overlay {
                    RadialGradient(
                        colors: [.white.opacity(0.38), .white.opacity(0)],
                        center: UnitPoint(x: 0.83, y: 0.47),
                        startRadius: 0, endRadius: width * 0.27
                    )
                }
                .overlay {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0.60),
                                .init(color: kind.accentColor.opacity(0.16), location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .mask {
                    Image(uiImage: AvatarLabCloudSilhouette.image)
                        .resizable()
                        .scaledToFit()
                }
                .frame(width: width, height: height)
                .shadow(color: kind.accentColor.opacity(0.16), radius: side * 0.05,
                        x: 0, y: side * 0.028)
                .offset(y: side * 0.045)

                face(in: side)
                stateMark(in: side)
            }
            .frame(width: side, height: side)
            .overlay(Circle().stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var generatedArt: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                Circle().fill(kind.backdropColor)

                bodyShape
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.38),
                                kind.bodyColor,
                                kind.accentColor.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        bodyShape.stroke(.white.opacity(0.72), lineWidth: side * 0.018)
                    }
                    .overlay {
                        bodyShape.stroke(kind.accentColor.opacity(0.28), lineWidth: side * 0.012)
                    }
                    .overlay {
                        // A compact gloss streak gives the flat shapes a soft, candy-like surface.
                        Ellipse()
                            .fill(LinearGradient(colors: [.white.opacity(0.76), .white.opacity(0.06)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: side * 0.24, height: side * 0.085)
                            .rotationEffect(.degrees(-34))
                            .offset(x: -side * 0.105, y: -side * 0.17)
                            .blur(radius: side * 0.006)
                            .mask(bodyShape)
                    }
                    .shadow(color: kind.accentColor.opacity(0.24), radius: side * 0.045,
                            x: side * 0.012, y: side * 0.035)
                    .frame(width: side * bodyWidth,
                           height: side * bodyHeight)
                    .offset(y: side * 0.045)

                accessory(in: side)
                face(in: side)
                stateMark(in: side)
            }
            .frame(width: side, height: side)
            .overlay(Circle().stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var bodyShape: AnyShape {
        switch kind {
        case .veraBean:
            AnyShape(AvatarLabBeanShape())
        case .sprout:
            AnyShape(AvatarLabWaterdropShape())
        case .star:
            AnyShape(AvatarLabStarShape())
        case .cloud:
            AnyShape(Rectangle()) // cloudArt renders the extracted alpha silhouette instead.
        case .sugar:
            AnyShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        }
    }

    private var bodyWidth: CGFloat {
        switch kind {
        case .cloud: 0.80
        case .sugar: 0.59
        case .veraBean: 0.44
        case .sprout: 0.62
        case .star: 0.69
        }
    }

    private var bodyHeight: CGFloat {
        switch kind {
        case .cloud: 0.55
        case .veraBean: 0.73
        case .sugar: 0.58
        case .star: 0.66
        case .sprout: 0.58
        }
    }

    @ViewBuilder
    private func accessory(in side: CGFloat) -> some View {
        switch kind {
        case .veraBean:
            Circle()
                .fill(LinearGradient(colors: [.white, kind.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: side * 0.105, height: side * 0.105)
                .shadow(color: kind.accentColor.opacity(0.32), radius: side * 0.025, y: side * 0.012)
                .offset(x: side * 0.14, y: -side * 0.23)
        case .sprout:
            HStack(spacing: -side * 0.035) {
                Ellipse().fill(LinearGradient(colors: [.white, kind.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: side * 0.16, height: side * 0.09).rotationEffect(.degrees(-32))
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.9), kind.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: side * 0.16, height: side * 0.09).rotationEffect(.degrees(32))
            }
            .shadow(color: kind.accentColor.opacity(0.25), radius: side * 0.02, y: side * 0.01)
            .offset(y: -side * 0.29)
        case .star:
            Image(systemName: "sparkle")
                .font(.system(size: side * 0.2, weight: .semibold))
                .foregroundStyle(kind.accentColor)
                .shadow(color: kind.accentColor.opacity(0.36), radius: side * 0.025, y: side * 0.012)
                .offset(x: side * 0.24, y: -side * 0.19)
        case .cloud:
            EmptyView()
        case .sugar:
            RoundedRectangle(cornerRadius: side * 0.025, style: .continuous)
                .fill(LinearGradient(colors: [.white, kind.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: side * 0.13, height: side * 0.10)
                .shadow(color: kind.accentColor.opacity(0.3), radius: side * 0.02, y: side * 0.01)
                .offset(y: -side * 0.32)
        }
    }

    private func face(in side: CGFloat) -> some View {
        // 思考时看向一侧；委派时看向另一侧（看向被委派的 Bot）
        let gaze = state == .thinking ? side * 0.025 : (state == .delegating ? -side * 0.035 : 0)
        let eyeHeight = side * (state == .done ? 0.075 : 0.095)

        return VStack(spacing: side * 0.075) {
            HStack(spacing: side * 0.16) {
                Capsule().fill(Color.avatarInk)
                    .frame(width: side * 0.06, height: eyeHeight)
                Capsule().fill(Color.avatarInk)
                    .frame(width: side * 0.06, height: eyeHeight)
            }
            .offset(x: gaze, y: side * (state == .thinking ? -0.018 : 0))

            mouth(in: side)
                .frame(width: side * 0.105, height: side * 0.045)
        }
        .overlay(alignment: .top) {
            HStack(spacing: side * 0.16) {
                Circle().fill(Color.avatarBlush.opacity(0.5)).frame(width: side * 0.07, height: side * 0.045)
                Circle().fill(Color.avatarBlush.opacity(0.5)).frame(width: side * 0.07, height: side * 0.045)
            }
            .offset(y: side * 0.065)
        }
        .offset(y: side * 0.06)
    }

    @ViewBuilder
    private func mouth(in side: CGFloat) -> some View {
        switch state {
        case .idle, .done:
            AvatarLabSmileShape()
                .stroke(Color.avatarInk, style: StrokeStyle(lineWidth: side * 0.018, lineCap: .round))
        case .thinking, .working, .delegating:
            Capsule().fill(Color.avatarInk).frame(width: side * 0.07, height: side * 0.018)
        case .replying:
            Ellipse().fill(Color.avatarInk).frame(width: side * 0.06, height: side * 0.04)
        case .waiting:
            Circle().fill(Color.avatarInk).frame(width: side * 0.025, height: side * 0.025)
        case .blocked:
            AvatarLabFrownShape()
                .stroke(Color.avatarInk, style: StrokeStyle(lineWidth: side * 0.018, lineCap: .round))
        }
    }

    @ViewBuilder
    private func stateMark(in side: CGFloat) -> some View {
        if state != .idle {
            // 右下角状态角标：避开顶部的配件（V豆的圆点、星点的闪光）；底色用语义色，深色模式下符号仍清晰
            ZStack {
                Circle().fill(Color.avatarMarkFill)
                Circle().stroke(kind.backdropColor, lineWidth: side * 0.014)
                Image(systemName: state.symbol)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.bold)
                    .frame(width: Self.badgeGlyphSide(side), height: Self.badgeGlyphSide(side))
                    .foregroundStyle(state == .blocked ? Color.avatarBlockedMark : kind.accentColor)
            }
            .frame(width: side * 0.26, height: side * 0.26)
            .shadow(color: .black.opacity(0.12), radius: side * 0.025, y: side * 0.01)
            .offset(x: side * 0.33, y: side * 0.33)
        }
    }

    @ViewBuilder
    private func moving<Content: View>(_ content: Content, phase: Bool) -> some View {
        switch state {
        case .idle:
            content.scaleEffect(phase ? 1.025 : 0.99)
        case .thinking:
            content.rotationEffect(.degrees(phase ? 2 : -2))
        case .working:
            content.offset(y: phase ? -size * 0.025 : size * 0.02)
        case .delegating:
            content.offset(x: phase ? -size * 0.03 : size * 0.01).rotationEffect(.degrees(phase ? -3 : 0))
        case .replying:
            content.scaleEffect(x: phase ? 0.99 : 1.0, y: phase ? 1.035 : 0.985, anchor: .bottom)
        case .waiting:
            content.rotationEffect(.degrees(phase ? -2.5 : 2.5))
        case .done:
            content.scaleEffect(phase ? 1.045 : 0.98)
        case .blocked:
            content.offset(x: phase ? size * 0.03 : -size * 0.015)   // 轻摇一下
        }
    }
}

/// 滚出滚动视图时把 `isVisible` 设为 false，持续状态的 `phaseAnimator` 会被卸掉。
/// iOS 18+ 用系统 `onScrollVisibilityChange`（按滚动视口，而不是整屏）；更早系统用全局 frame 与屏幕是否相交。
private struct AvatarScrollVisibility: ViewModifier {
    var enabled: Bool
    @Binding var isVisible: Bool
    @Binding var scrollVisibilityKnown: Bool

    func body(content: Content) -> some View {
        if enabled {
            tracked(content)
        } else {
            content
        }
    }

    @ViewBuilder
    private func tracked(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0) { visible in
                scrollVisibilityKnown = true
                if isVisible != visible { isVisible = visible }
            }
        } else {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(key: AvatarGlobalFrameKey.self, value: proxy.frame(in: .global))
                }
            }
            .onPreferenceChange(AvatarGlobalFrameKey.self) { frame in
                guard frame.width > 1, frame.height > 1 else { return }
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let bounds = scenes.first?.screen.bounds else { return }
                scrollVisibilityKnown = true
                let visible = frame.intersects(bounds)
                if isVisible != visible { isVisible = visible }
            }
        }
    }
}

private struct AvatarGlobalFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

@MainActor
private enum AvatarLabCloudSilhouette {
    static let image: UIImage = {
        guard let source = UIImage(named: "AvatarLabCloudReference")?.cgImage else { return UIImage() }
        let width = source.width
        let height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        return pixels.withUnsafeMutableBytes { bytes -> UIImage in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return UIImage() }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let buffer = bytes.bindMemory(to: UInt8.self)
            let background = (0..<3).map { Double(buffer[$0]) }
            let direction = background.map { 255 - $0 }
            let denominator = direction.reduce(0) { $0 + $1 * $1 }
            guard denominator > 0 else { return UIImage() }
            var minX = width, minY = height, maxX = -1, maxY = -1

            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    // Recover the source's white-cloud coverage against its uniform blue backdrop.
                    // Keep the original edge coverage instead of approximating the silhouette with curves.
                    var coverage = 0.0
                    for channel in 0..<3 {
                        coverage += (Double(buffer[offset + channel]) - background[channel]) * direction[channel]
                    }
                    coverage = min(1, max(0, coverage / denominator))
                    let alpha = coverage > 0.01 ? UInt8((coverage * 255).rounded()) : 0
                    for channel in 0..<4 { buffer[offset + channel] = alpha }
                    if alpha > 0 {
                        minX = min(minX, x); minY = min(minY, y)
                        maxX = max(maxX, x); maxY = max(maxY, y)
                    }
                }
            }
            guard maxX >= minX, maxY >= minY,
                  let mask = context.makeImage()?.cropping(to: CGRect(
                    x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1
                  )) else { return UIImage() }
            return UIImage(cgImage: mask)
        }
    }()

    static var aspectRatio: CGFloat {
        image.size.height > 0 ? image.size.width / image.size.height : 1.5
    }
}

private struct AvatarLabBeanShape: Shape {
    // Normalized silhouette traced from the reference's bean body only.
    // The left indentation and full right side retain its upright, asymmetric outline.
    private static let outline: [CGPoint] = [
        CGPoint(x: 0.08367, y: 0.43227),
        CGPoint(x: 0.00000, y: 0.26724),
        CGPoint(x: 0.00816, y: 0.16010),
        CGPoint(x: 0.05714, y: 0.09483),
        CGPoint(x: 0.14286, y: 0.04310),
        CGPoint(x: 0.25102, y: 0.01355),
        CGPoint(x: 0.37143, y: 0.00000),
        CGPoint(x: 0.52041, y: 0.01355),
        CGPoint(x: 0.74694, y: 0.09236),
        CGPoint(x: 0.92449, y: 0.24384),
        CGPoint(x: 1.00000, y: 0.41379),
        CGPoint(x: 0.97959, y: 0.60837),
        CGPoint(x: 0.89592, y: 0.77340),
        CGPoint(x: 0.73673, y: 0.91010),
        CGPoint(x: 0.62653, y: 0.95567),
        CGPoint(x: 0.52245, y: 0.98768),
        CGPoint(x: 0.37143, y: 1.00000),
        CGPoint(x: 0.25102, y: 0.98645),
        CGPoint(x: 0.09592, y: 0.91626),
        CGPoint(x: 0.02245, y: 0.82266),
        CGPoint(x: 0.01429, y: 0.72414),
        CGPoint(x: 0.09184, y: 0.51970)
    ]

    func path(in rect: CGRect) -> Path {
        let points = Self.outline.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
        }
        var path = Path()
        path.move(to: points[0])
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let following = points[(index + 2) % points.count]
            path.addCurve(
                to: next,
                control1: CGPoint(x: current.x + (next.x - previous.x) / 6,
                                  y: current.y + (next.y - previous.y) / 6),
                control2: CGPoint(x: next.x - (following.x - current.x) / 6,
                                  y: next.y - (following.y - current.y) / 6)
            )
        }
        path.closeSubpath()
        return path
    }
}

private struct AvatarLabWaterdropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.035))
        path.addCurve(to: CGPoint(x: rect.width * 0.08, y: rect.height * 0.60),
                      control1: CGPoint(x: rect.width * 0.38, y: rect.height * 0.12),
                      control2: CGPoint(x: rect.width * 0.08, y: rect.height * 0.35))
        path.addCurve(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.965),
                      control1: CGPoint(x: rect.width * 0.08, y: rect.height * 0.84),
                      control2: CGPoint(x: rect.width * 0.27, y: rect.height * 0.965))
        path.addCurve(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.60),
                      control1: CGPoint(x: rect.width * 0.73, y: rect.height * 0.965),
                      control2: CGPoint(x: rect.width * 0.92, y: rect.height * 0.84))
        path.addCurve(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.035),
                      control1: CGPoint(x: rect.width * 0.92, y: rect.height * 0.35),
                      control2: CGPoint(x: rect.width * 0.62, y: rect.height * 0.12))
        path.closeSubpath()
        return path
    }
}

private struct AvatarLabStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.49
        let innerRadius = radius * 0.68
        let points = (0..<10).map { index -> CGPoint in
            let angle = -Double.pi / 2 + Double(index) * Double.pi / 5
            let pointRadius = index.isMultiple(of: 2) ? radius : innerRadius
            return CGPoint(x: center.x + CGFloat(cos(angle)) * pointRadius,
                           y: center.y + CGFloat(sin(angle)) * pointRadius)
        }

        func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
            CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        }

        var path = Path()
        path.move(to: midpoint(points[9], points[0]))
        for index in 0..<10 {
            path.addQuadCurve(to: midpoint(points[index], points[(index + 1) % 10]),
                              control: points[index])
        }
        path.closeSubpath()
        return path
    }
}

private struct AvatarLabSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.maxY * 1.8))
        return path
    }
}

private struct AvatarLabFrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.7))
        return path
    }
}
