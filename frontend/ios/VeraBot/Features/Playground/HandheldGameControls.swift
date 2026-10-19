import SwiftUI

/// 受掌机启发、可触摸的实体按键。保留按压行程 + 触感（沿用 hapticFeedback 包装，遵守
/// 「触感反馈」开关与「减少动态效果」），可选按住连续触发；命中区 ≥44pt。
struct GameKey<Label: View>: View {
    let shape: AnyShape
    var heavyImpact = false
    var repeatInterval: TimeInterval? = nil
    var accessibilityLabelText: String?
    let action: () -> Void
    let label: Label

    @State private var isPressing = false
    @State private var repeatTask: Task<Void, Never>?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(shape: AnyShape,
         heavyImpact: Bool = false,
         repeatInterval: TimeInterval? = nil,
         accessibilityLabelText: String? = nil,
         action: @escaping () -> Void,
         @ViewBuilder label: () -> Label) {
        self.shape = shape
        self.heavyImpact = heavyImpact
        self.repeatInterval = repeatInterval
        self.accessibilityLabelText = accessibilityLabelText
        self.action = action
        self.label = label()
    }

    var body: some View {
        let pressed = isPressing && isEnabled
        label
            .foregroundStyle(Color.brand)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color.sectionFill, in: shape)
            .overlay {
                shape.fill(Color.primary.opacity(pressed ? 0.07 : 0)).allowsHitTesting(false)
            }
            .overlay {
                shape.stroke(Color.primary.opacity(pressed ? 0.17 : 0.08), lineWidth: 1).allowsHitTesting(false)
            }
            .offset(y: pressed && !reduceMotion ? 2 : 0)
            .background {
                shape.fill(Color.primary.opacity(0.16)).offset(y: 3)
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.7), value: pressed)
            .hapticFeedback(
                .impact(weight: heavyImpact ? .heavy : .medium, intensity: heavyImpact ? 0.85 : 0.65),
                trigger: isPressing
            ) { wasPressing, isNowPressing in
                isEnabled && !wasPressing && isNowPressing
            }
            .gesture(pressGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabelText ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in startPress() }
            .onEnded { _ in endPress() }
    }

    private func startPress() {
        guard isEnabled, !isPressing else { return }
        isPressing = true
        action()
        guard let interval = repeatInterval else { return }
        repeatTask?.cancel()
        repeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
                guard !Task.isCancelled, isPressing else { return }
                action()
            }
        }
    }

    private func endPress() {
        isPressing = false
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// 一体十字方向键。上方向可留空（俄罗斯方块不绑定硬降），其余方向按住连续触发。
struct GameDpad: View {
    var onUp: (() -> Void)?
    let onDown: () -> Void
    let onLeft: () -> Void
    let onRight: () -> Void
    var repeatInterval: TimeInterval? = 0.11

    private let key: CGFloat = 50
    private let gap: CGFloat = 2

    init(onUp: (() -> Void)? = nil,
         onDown: @escaping () -> Void,
         onLeft: @escaping () -> Void,
         onRight: @escaping () -> Void,
         repeatInterval: TimeInterval? = 0.11) {
        self.onUp = onUp
        self.onDown = onDown
        self.onLeft = onLeft
        self.onRight = onRight
        self.repeatInterval = repeatInterval
    }

    var body: some View {
        VStack(spacing: gap) {
            arm("chevron.up", "向上", action: onUp)
            HStack(spacing: gap) {
                arm("chevron.left", "向左", action: onLeft)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.sectionFill)
                    .frame(width: key, height: key)
                    .accessibilityHidden(true)
                arm("chevron.right", "向右", action: onRight)
            }
            arm("chevron.down", "向下", action: onDown)
        }
    }

    private func arm(_ symbol: String, _ text: String, action: (() -> Void)?) -> some View {
        GameKey(
            shape: AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous)),
            repeatInterval: action == nil ? nil : repeatInterval,
            accessibilityLabelText: text,
            action: action ?? {}
        ) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: key, height: key)
        }
        .disabled(action == nil)
    }
}

/// 右侧斜排圆形 A / B。A 旋转（上），B 直接落下（下，偏右）；中文标签放在圆外。
struct GameFaceCluster: View {
    let onA: () -> Void
    let onB: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                Button(action: onA) {
                    Text("A")
                        .font(.title3.bold().monospacedDigit())
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(GameButtonStyle(shape: AnyShape(Circle())))
                .accessibilityLabel("旋转")
                Text("旋转").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                Button(action: onB) {
                    Text("B")
                        .font(.title3.bold().monospacedDigit())
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(GameButtonStyle(heavyImpact: true, shape: AnyShape(Circle())))
                .accessibilityLabel("直接落下")
                Text("直接落下").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 22)
        }
    }
}

/// 下中小胶囊键（START / SELECT）。
struct GamePillKey: View {
    let title: String
    let systemImage: String
    var heavyImpact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
        }
        .buttonStyle(GameButtonStyle(heavyImpact: heavyImpact, shape: AnyShape(Capsule())))
    }
}
