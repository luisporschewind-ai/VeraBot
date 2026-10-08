import SwiftUI
import UIKit

// Native study of CX ArtLab's Agent Robot Avatar (MIT).
// Geometry/pose proportions adapted from the original; see docs/design/ROBOT_AVATAR_LAB.md.
enum RobotAvatarAction: String, CaseIterable, Identifiable {
    case idle, bored, waiting
    case waitingWrap = "waiting-wrap"
    case input, send, success, failure, warning, inspect, blocked, error, surprise, sleep, wake, love, random
    var id: String { rawValue }
    var title: String {
        switch self {
        case .idle: "正常"
        case .bored: "发呆"
        case .waiting: "等待"
        case .waitingWrap: "等待 · 环绕"
        case .input: "输入"
        case .send: "发送 / 点头"
        case .success: "成功"
        case .failure: "失败"
        case .warning: "警告"
        case .inspect: "审视"
        case .blocked: "内容阻止"
        case .error: "系统错误"
        case .surprise: "惊讶"
        case .sleep: "睡着"
        case .wake: "醒来"
        case .love: "喜欢"
        case .random: "随机"
        }
    }
    var detail: String {
        switch self {
        case .idle: "自然眨眼，偶尔看向四周"
        case .bored: "抬眼看向左上、右上，再回到中央"
        case .waiting: "双眼交叉绕行，随前后位置改变大小"
        case .waitingWrap: "双眼绕过头部，在背面隐去再出现"
        case .input: "双眼收成竖向光标，同步闪烁"
        case .send: "连续点两次头，第二次缓缓回正"
        case .success: "笑眼和短促的轻弹"
        case .failure: "眼睑下垂，表示任务未完成"
        case .warning: "近眼放大、远眼收窄，眼睑下压再抬起"
        case .inspect: "眯起双眼，上下观察后重新睁开"
        case .blocked: "收紧眼神，轻摇一次"
        case .error: "双眼左右扫动，头部随后左右摇动"
        case .surprise: "先收缩，再睁大双眼"
        case .sleep: "双眼合上，头部轻垂"
        case .wake: "睁开眼睛，重新抬头"
        case .love: "两只眼睛各变为一颗心，轻跳后回正"
        case .random: "双眼滚动，先后减速并回弹停下"
        }
    }
    var continuous: Bool { self == .input }
}

enum RobotAvatarTone: String, CaseIterable, Identifiable {
    case graphite, violet, blue
    var id: String { rawValue }
    var title: String {
        switch self { case .graphite: "石墨"; case .violet: "深紫"; case .blue: "深蓝" }
    }
    var color: Color {
        switch self {
        case .graphite: Color(red: 0.031, green: 0.035, blue: 0.043)
        case .violet: Color(red: 0.19, green: 0.13, blue: 0.29)
        case .blue: Color(red: 0.10, green: 0.19, blue: 0.28)
        }
    }
}

/// A single view-owned clock drives poses and the independent antenna spring.
struct RobotAvatarView: View {
    let action: RobotAvatarAction
    var size: CGFloat = 160
    var roundness = 0.5
    var color: Color = RobotAvatarTone.graphite.color
    var ambient = true
    var replay = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var elapsed = 0.0
    @State private var gaze = CGSize.zero
    @State private var blink = 1.0
    @State private var antenna = CGPoint(x: 120, y: 12)
    @State private var antennaVelocity = CGVector.zero
    @State private var tapReplay = 0
    @State private var interaction = RobotAvatarInteraction()
    @GestureState private var fingerDown = false

    private var active: Bool { visible && scenePhase == .active && !reduceMotion }
    // The antenna extends above the 240-point viewport; its spring needs extra drawing room.
    private var drawingOverflow: CGFloat { size / 240 * 40 }
    private var taskKey: String { "\(action.rawValue)|\(replay)|\(tapReplay)|\(active)|\(ambient)" }

    var body: some View {
        ZStack {
          Canvas { context, canvasSize in
            let scale = size / 240
            context.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -120, y: -120)
            let frame = currentFrame()
            let headPath = RobotAvatarGeometry.head(roundness: roundness, interaction: interaction)
            var head = context
            head.concatenate(headTransform(frame))
            head.fill(headPath, with: .color(color))
            head.clip(to: headPath)
            for eye in frame.eyes {
                var eyeContext = head
                eyeContext.translateBy(x: 120 + eye.x, y: 120 + eye.y)
                eyeContext.scaleBy(x: eye.scaleX, y: eye.scaleY)
                eyeContext.opacity = eye.opacity
                let path = eye.heart > 0 ? RobotAvatarGeometry.heart(eye) : RobotAvatarGeometry.eye(eye, blink: allowsAmbient ? blink : 1)
                eyeContext.fill(path, with: .color(Color(red: 248.0 / 255, green: 248.0 / 255, blue: 246.0 / 255)))
            }
            let point = displayedAntenna
            let stretch = interaction.kind == .antenna ? max(-0.06, min(0.06, interaction.y.velocity * 0.0004)) : 0
            context.opacity = frame.antennaOpacity
            context.fill(Path(ellipseIn: CGRect(x: point.x - 15 * (1 + stretch), y: point.y - 15 * (1 - stretch),
                                               width: 30 * (1 + stretch), height: 30 * (1 - stretch))), with: .color(color))
          }
          .accessibilityHidden(true)
          Color.clear
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("机器人，\(action.title)")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("拖动头部体验形变，按住中心挤压，轻点重播")
            .accessibilityAction { tapReplay += 1 }
          Color.clear
            .frame(width: max(20, size / 240 * 36), height: max(20, size / 240 * 36))
            .contentShape(Circle())
            .position(x: drawingOverflow + displayedAntenna.x * size / 240,
                      y: drawingOverflow + displayedAntenna.y * size / 240)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("机器人天线")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("可独立向任意方向拖动，松手弹回")
        }
        .frame(width: size + drawingOverflow * 2, height: size + drawingOverflow * 2)
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 0)
            .updating($fingerDown) { _, current, _ in current = true }
            .onChanged { value in
                if !interaction.held {
                    let point = CGPoint(x: (value.startLocation.x - drawingOverflow) * 240 / size,
                                        y: (value.startLocation.y - drawingOverflow) * 240 / size)
                    interaction.begin(at: point, size: size, antenna: displayedAntenna,
                                      antennaVisible: currentFrame().antennaOpacity > 0.01, reduced: reduceMotion)
                }
                interaction.move(translation: value.translation, reduced: reduceMotion)
            }
            .onEnded { value in
                interaction.move(translation: value.translation, reduced: reduceMotion)
                if interaction.end(reduced: reduceMotion) { tapReplay += 1 }
            })
        .onChange(of: fingerDown) { _, down in
            // Gesture cancellation (e.g. navigation/scroll interruption) cannot leave a held press.
            if !down && interaction.held { _ = interaction.end(reduced: reduceMotion) }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .contain)
        .modifier(RobotScrollVisibility(visible: $visible))
        .onAppear { visible = true }
        .onDisappear { visible = false; interaction = .init() }
        .task(id: taskKey) { await runMotion() }
    }

    private var allowsAmbient: Bool {
        if interaction.overridesAction {
            return ambient && interaction.kind == .none &&
                (interaction.reaction == nil || interaction.reactionAge >= 2000)
        }
        return ambient && (action == .idle || action == .bored || (action != .sleep && elapsed >= RobotAvatarMotion.duration(action)))
    }
    private var displayedAntenna: CGPoint {
        if interaction.kind == .squeeze { return interaction.squeezePose.antenna }
        if interaction.kind == .antenna { return CGPoint(x: interaction.home.x + interaction.x.position, y: interaction.home.y + interaction.y.position) }
        return active ? antenna : CGPoint(x: 120, y: 12).applying(headTransform(currentFrame()))
    }
    private func currentFrame() -> RobotAvatarMotion.Frame {
        var frame = interaction.overridesAction ? RobotAvatarMotion.Frame() : RobotAvatarMotion.sample(action, ms: elapsed, reduced: reduceMotion)
        if interaction.overridesAction, interaction.kind == .none, interaction.reaction != nil {
            frame = interaction.reactionFrame(reduced: reduceMotion)
        }
        if interaction.kind == .squeeze {
            for i in 0..<2 {
                frame.eyes[i].x += (i == 0 ? 24 : -24) * interaction.squeeze.position
                frame.eyes[i].width = max(0, 54 - 31 * interaction.squeeze.position)
                frame.eyes[i].height = max(0.1, 58 - 20 * interaction.squeeze.position)
            }
        } else if interaction.kind == .antenna {
            for i in 0..<2 { frame.eyes[i].x += interaction.look.x; frame.eyes[i].y += interaction.look.y }
        } else if interaction.kind == .head {
            for i in 0..<2 {
                let offset = interaction.deformation(at: CGPoint(x: 120 + frame.eyes[i].x, y: 126))
                frame.eyes[i].x += offset.x * 0.24 + interaction.look.x
                frame.eyes[i].y += offset.y * 0.24 + interaction.look.y
            }
            frame.headRotation += interaction.lookRotation.position
        }
        if allowsAmbient, interaction.overridesAction || action != .bored || elapsed >= RobotAvatarMotion.duration(.bored) {
            for i in 0..<2 { frame.eyes[i].x += gaze.width; frame.eyes[i].y += gaze.height }
        }
        // Original edge perspective: the eye nearer the silhouette compresses and shifts inward.
        if interaction.overridesAction || ![.waiting, .waitingWrap, .warning, .random, .love].contains(action) {
            for i in 0..<2 where frame.eyes[i].cursor == 0 {
                let eye = frame.eyes[i]
                let distance = i == 0 ? eye.x + 88 : 88 - eye.x
                let edge = RobotAvatarMotion.clamp(1 - distance / 58)
                let w = eye.width * (1 - 0.22 * edge * edge)
                frame.eyes[i].width = w
                frame.eyes[i].height *= 1 - 0.08 * edge * edge
                frame.eyes[i].x += (eye.width - w) * 0.58 * (i == 0 ? 1 : -1)
            }
        }
        return frame
    }
    private func headTransform(_ frame: RobotAvatarMotion.Frame) -> CGAffineTransform {
        let base = CGAffineTransform(translationX: 120 + frame.headX, y: 120 + frame.headY)
            .rotated(by: frame.headRotation * .pi / 180)
            .scaledBy(x: frame.headScale, y: frame.headScale)
            .translatedBy(x: -120, y: -120)
        switch interaction.kind {
        case .squeeze:
            let pose = interaction.squeezePose
            return CGAffineTransform(translationX: 120 + pose.x, y: 120 + pose.y)
                .scaledBy(x: pose.scaleX, y: pose.scaleY).translatedBy(x: -120, y: -120)
        case .antenna:
            return CGAffineTransform(translationX: 120 + interaction.headX.position * 0.12, y: 120 + interaction.headY.position * 0.12)
                .rotated(by: interaction.headX.position * 0.08 * .pi / 180).translatedBy(x: -120, y: -120)
        case .head:
            let anchor = interaction.anchor
            let pose = CGAffineTransform(translationX: anchor.x + interaction.x.position, y: anchor.y + interaction.y.position)
                .rotated(by: interaction.angle)
                .scaledBy(x: 1 + interaction.stretch.position, y: 1 - interaction.stretch.position * 0.30)
            let drag = CGAffineTransform(a: 1, b: interaction.shear.position, c: 0, d: 1, tx: 0, ty: 0).concatenating(pose)
                .rotated(by: -interaction.angle).translatedBy(x: -anchor.x, y: -anchor.y)
            return base.concatenating(drag)
        default: return base
        }
    }

    @MainActor
    private func runMotion() async {
        elapsed = 0; gaze = .zero; blink = 1
        interaction = .init()
        antenna = CGPoint(x: 120, y: 12); antennaVelocity = .zero
        guard active else { return }
        let start = Date()
        var previous = start
        var nextBlink = Double.random(in: 2200...4500)
        var blinkStart: Double?
        var nextLook = Double.random(in: 2400...5000)
        var targetGaze = CGSize.zero
        do {
            while !Task.isCancelled {
                let now = Date()
                let dt = max(0.001, min(0.05, now.timeIntervalSince(previous)))
                previous = now
                elapsed = now.timeIntervalSince(start) * 1000
                interaction.advance(dt: dt, reduced: reduceMotion)
                if allowsAmbient {
                    if elapsed >= nextBlink, blinkStart == nil { blinkStart = elapsed }
                    if let begin = blinkStart {
                        let k = (elapsed - begin) / 190
                        blink = k < 0.5 ? 1 - 0.92 * k * 2 : 0.08 + 0.92 * min(1, (k - 0.5) * 2)
                        if k >= 1 { blink = 1; blinkStart = nil; nextBlink = elapsed + Double.random(in: 2200...4500) }
                    }
                    if elapsed >= nextLook, action != .bored || elapsed >= RobotAvatarMotion.duration(.bored) {
                        targetGaze = CGSize(width: Double.random(in: -12...12), height: Double.random(in: -6...6))
                        nextLook = elapsed + Double.random(in: 2400...5000)
                    }
                    let k = 1 - pow(0.84, dt / 0.01667)
                    gaze.width += (targetGaze.width - gaze.width) * k
                    gaze.height += (targetGaze.height - gaze.height) * k
                }
                let target = CGPoint(x: 120, y: 12).applying(headTransform(currentFrame()))
                // Independent upstream spring: stiffness 180, damping 5.6. The dot trails the head.
                antennaVelocity.dx += ((target.x - antenna.x) * 180 - antennaVelocity.dx * 5.6) * dt
                antennaVelocity.dy += ((target.y - antenna.y) * 180 - antennaVelocity.dy * 5.6) * dt
                antenna.x += antennaVelocity.dx * dt
                antenna.y += antennaVelocity.dy * dt
                try await Task.sleep(for: .milliseconds(16))
            }
        } catch { /* View-owned cancellation when hidden, replaced, or backgrounded. */ }
    }
}

private struct RobotAvatarFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct RobotScrollVisibility: ViewModifier {
    @Binding var visible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
        } else {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(key: RobotAvatarFrameKey.self, value: proxy.frame(in: .global))
                }
            }
            .onPreferenceChange(RobotAvatarFrameKey.self) { frame in
                guard frame.width > 1, frame.height > 1 else { return }
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let bounds = scenes.first?.screen.bounds else { return }
                visible = frame.intersects(bounds)
            }
        }
    }
}
