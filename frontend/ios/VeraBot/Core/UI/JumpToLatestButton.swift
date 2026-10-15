import SwiftUI

/// 对话列表滚离底部时显示的圆形「回到最新」按钮（私聊 / 群聊共用）。
/// 仅图标，无文案、无未读数；贴输入栏上方右侧，贴底时淡出隐藏。
struct JumpToLatestButton: View {
    let visible: Bool
    let action: () -> Void

    private let size: CGFloat = 40

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .modifier(JumpToLatestGlassBackground())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到最新消息")
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.2), value: visible)
    }
}

/// iOS 26 用系统 `.glassEffect`；旧系统回退到 `.ultraThinMaterial` 圆形底。
private struct JumpToLatestGlassBackground: ViewModifier {
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
