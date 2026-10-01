import SwiftUI
import VeraBotCore

/// 触感反馈统一入口：所有 sensoryFeedback 都走这里，受「设置 › 触感反馈」开关控制（默认开启）。
private struct GatedSensoryFeedback<Trigger: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: Trigger
    @AppStorage(SettingsKeys.hapticsEnabled) private var enabled = true

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { _, _ in enabled }
    }
}

extension View {
    /// 系统 sensoryFeedback 的包装；关闭「触感反馈」后不再播放。
    func hapticFeedback<Trigger: Equatable>(_ feedback: SensoryFeedback, trigger: Trigger) -> some View {
        modifier(GatedSensoryFeedback(feedback: feedback, trigger: trigger))
    }
}
