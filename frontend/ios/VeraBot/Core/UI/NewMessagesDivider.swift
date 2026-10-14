import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 未读新回复分隔线（私聊 / 群聊共用）。Boss 参考：浅蓝色细发丝线贯通宽度，
/// 正中「新」小号蓝字、线在字两侧留白断开；无 pill / capsule / 底色。
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
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("以下是新消息")
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
