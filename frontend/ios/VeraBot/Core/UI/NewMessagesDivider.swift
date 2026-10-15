import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 未读新回复分隔线（私聊 / 群聊共用）。正中小号「新」，两侧淡淡的浅蓝色横线；
/// 不在 Bot 头像或气泡上方另挂「新消息」。无 pill / capsule / 底色。
struct NewMessagesDivider: View {
    private let tint = Color(red: 0.45, green: 0.64, blue: 0.95)

    var body: some View {
        HStack(spacing: 10) {
            hairline
            Text("新")
                .font(.caption2)
                .foregroundStyle(tint)
            hairline
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("新消息")
    }

    private var hairline: some View {
        Rectangle()
            .fill(tint.opacity(0.45))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
