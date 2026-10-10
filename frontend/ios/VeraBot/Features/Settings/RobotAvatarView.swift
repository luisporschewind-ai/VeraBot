import SwiftUI
import UIKit
import VeraBotCore

// Native study of CX ArtLab's Agent Robot Avatar (MIT).
// Geometry/pose proportions adapted from the original; see docs/design/ROBOT_AVATAR_LAB.md.
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
    var appearance: BotAppearance? = nil
    var skin: BotAvatarSkin? = nil
    var familyLook = BotAvatarFamilyLook()
    var staticPreview = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var elapsed = 0.0
    @State private var gaze = CGSize.zero
    @State private var blink = 1.0
    @State private var motionAmbient = true
    @State private var antenna = CGPoint(x: 120, y: 12)
    @State private var antennaVelocity = CGVector.zero
    @State private var tapReplay = 0
    @State private var interaction = RobotAvatarInteraction()
    @State private var previousAction: RobotAvatarAction = .idle
    @State private var lastMotionFrame = RobotAvatarMotion.Frame()
    @State private var entryPose: RobotAvatarMotion.Frame?
    @GestureState private var fingerDown = false

    private var active: Bool { visible && scenePhase == .active && !reduceMotion && !staticPreview }
    // The antenna extends above the 240-point viewport; its spring needs extra drawing room.
    private var template: BotAvatarTemplate {
        var value = BotAvatarTemplateRegistry.resolve(id:appearance?.templateID ?? "cx-robot",version:appearance?.templateVersion ?? 1) ?? .robot
        if let seed = familyLook.shape.seed {
            value.antennaAnchor = RobotAvatarFamilyGeometry.antenna(seed:seed,roundness:appearance?.parameters.roundness ?? roundness)
        }
        return value
    }
    private var activeSkin: BotAvatarSkin? { familyLook.skin ?? skin }
    private var bodyColor: Color { appearance?.palette.body.swiftUIColor ?? color }
    private var eyeColor: Color { appearance?.palette.eyes.swiftUIColor ?? Color(red:248.0/255,green:248.0/255,blue:246.0/255) }
    private var drawingOverflow: CGFloat { size / 240 * template.drawingMargin }
    private var taskKey: String { "\(action.rawValue)|\(replay)|\(tapReplay)|\(active)|\(familyLook.shape.rawValue)" }

    var body: some View {
        ZStack {
          Canvas { context, canvasSize in
            let scale = size / 240
            context.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -120, y: -120)
            let frame = currentFrame()
            let headPath = BotAvatarTemplateGeometry.head(template:template,parameters:appearance?.parameters ?? .init(roundness:roundness),interaction:interaction,familyShape:familyLook.shape)
            var head = context
            head.concatenate(headTransform(frame))
            head.clip(to: headPath)
            if let activeSkin {
                let surface = BotAvatarTemplateGeometry.head(template:template,parameters:appearance?.parameters ?? .init(roundness:roundness),interaction:.init(),familyShape:familyLook.shape)
                RobotAvatarSkinRendering.draw(activeSkin,surface:surface,interaction:interaction,in:&head)
            }
            else { head.fill(headPath, with:.color(bodyColor)) }
            for eye in frame.eyes {
                var eyeContext = head
                eyeContext.translateBy(x: 120 + eye.x, y: 120 + eye.y)
                eyeContext.scaleBy(x: eye.scaleX, y: eye.scaleY)
                eyeContext.opacity = eye.opacity
                let path: Path
                if eye.star > 0.001 { path = RobotAvatarGeometry.star(eye,progress:eye.star) }
                else if eye.heart > 0 { path = RobotAvatarGeometry.heart(eye) }
                else if eye.smile > 0.001 { path = RobotAvatarGeometry.crescent(eye) }
                else { path = RobotAvatarGeometry.eye(eye,blink:allowsAmbient ? blink : 1) }
                eyeContext.fill(path, with: .color(eyeColor))
            }
            var adornment = context
            adornment.concatenate(headTransform(frame))
            RobotAvatarAccessoryRendering.draw(familyLook.accessory,badge:familyLook.badgeStyle,head:headPath,color:eyeColor,bodyColor:bodyColor,in:&adornment)
            let point = displayedAntenna
            let stretch = interaction.kind == .antenna ? max(-0.06, min(0.06, interaction.y.velocity * 0.0004)) : 0
            context.opacity = frame.antennaOpacity
            context.fill(Path(ellipseIn: CGRect(x: point.x - template.antennaRadius * (1 + stretch), y: point.y - template.antennaRadius * (1 - stretch),
                                               width: template.antennaRadius * 2 * (1 + stretch), height: template.antennaRadius * 2 * (1 - stretch))), with: .color(activeSkin.map(RobotAvatarSkinRendering.antennaColor) ?? bodyColor))
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
                                      antennaVisible: template.capabilities.contains(.antenna) && currentFrame().antennaOpacity > 0.01, reduced: reduceMotion, antennaRadius:template.antennaRadius)
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
        .onAppear { visible = true; motionAmbient = ambient }
        .onChange(of: ambient) { _, value in
            motionAmbient = value
            if !value { gaze = .zero; blink = 1 }
        }
        .onDisappear { visible = false; interaction = .init() }
        .task(id: taskKey) { await runMotion() }
    }

    private var allowsAmbient: Bool {
        if interaction.overridesAction {
            return motionAmbient && interaction.kind == .none &&
                (interaction.reaction == nil || interaction.reactionAge >= 2000)
        }
        return motionAmbient && (action == .idle || action == .bored || (action != .sleep && elapsed >= RobotAvatarMotion.duration(action)))
    }
    private var displayedAntenna: CGPoint {
        if interaction.kind == .squeeze { return interaction.squeezePose.antenna }
        if interaction.kind == .antenna { return CGPoint(x: interaction.home.x + interaction.x.position, y: interaction.home.y + interaction.y.position) }
        let frame = currentFrame()
        let anchor = CGPoint(x:template.antennaAnchor.x+frame.antennaOffsetX,y:template.antennaAnchor.y+frame.antennaOffsetY)
        return active ? antenna : anchor.applying(headTransform(frame))
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
        let adapted = template.adapt(frame)
        if !interaction.overridesAction, let entryPose, elapsed < 200, !reduceMotion {
            return BotAvatarWorkMotion.enter(from:entryPose,to:adapted,ms:elapsed)
        }
        return adapted
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
        let enteringWork = active && previousAction != action && action.category == .work
        entryPose = enteringWork ? lastMotionFrame : nil
        previousAction = action
        elapsed = 0; gaze = .zero; blink = 1
        interaction = .init()
        if !enteringWork { antenna = template.antennaAnchor; antennaVelocity = .zero }
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
                let frame = currentFrame()
                lastMotionFrame = frame
                let target = CGPoint(x:template.antennaAnchor.x+frame.antennaOffsetX,y:template.antennaAnchor.y+frame.antennaOffsetY).applying(headTransform(frame))
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
