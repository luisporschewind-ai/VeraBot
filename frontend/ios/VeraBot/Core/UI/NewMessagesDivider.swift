import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 未读新回复分隔线（私聊 / 群聊共用）。正中「新消息」，两侧浅蓝色细发丝线；
/// 不在 Bot 头像或气泡上方另挂未读提示。无 pill / capsule / 底色。
struct NewMessagesDivider: View {
    private let tint = Color(red: 0.45, green: 0.64, blue: 0.95)

    var body: some View {
        HStack(spacing: 10) {
            hairline
            Text("新消息")
                .font(.caption)
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
            .fill(tint)
            .frame(height: hairlineHeight)
            .frame(maxWidth: .infinity)
    }

    private var hairlineHeight: CGFloat {
        #if canImport(UIKit)
        1 / UIScreen.main.scale
        #else
        0.5
        #endif
    }
}
