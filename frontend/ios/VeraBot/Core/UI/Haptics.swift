import SwiftUI
import VeraBotCore

/// 触感反馈统一入口：所有 sensoryFeedback 都走这里，受「设置 › 触感反馈」开关控制（默认开启）。
private struct GatedSensoryFeedback<Trigger: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: Trigger
    let condition: (Trigger, Trigger) -> Bool
    @AppStorage(SettingsKeys.hapticsEnabled) private var enabled = true

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { oldValue, newValue in
            enabled && condition(oldValue, newValue)
        }
    }
}

extension View {
    /// 系统 sensoryFeedback 的包装；关闭「触感反馈」后不再播放。
    func hapticFeedback<Trigger: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: Trigger,
        condition: @escaping (Trigger, Trigger) -> Bool = { _, _ in true }
    ) -> some View {
        modifier(GatedSensoryFeedback(feedback: feedback, trigger: trigger, condition: condition))
    }
}

/// 游戏实体按键：保留系统 Button 的点击/无障碍行为，只在按下沿触发一次触感。
struct GameButtonStyle: ButtonStyle {
    enum Tone { case standard, primary, secondary }
    var tone: Tone = .standard
    var heavyImpact = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        let filled = tone == .primary && appearance != "native"
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        return configuration.label
            .foregroundStyle(filled ? Color.white : (tone == .primary ? Color.primary : Color.brand))
            .background(filled ? Color.brandFill : (tone == .secondary ? Color.brandSoft : Color.sectionFill), in: shape)
            .overlay {
                shape.fill(Color.primary.opacity(pressed ? 0.07 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.stroke(Color.primary.opacity(pressed ? 0.17 : 0.08), lineWidth: 1)
                    .allowsHitTesting(false)
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
                trigger: configuration.isPressed
            ) { wasPressed, isPressed in
                isEnabled && !wasPressed && isPressed
            }
    }
}
