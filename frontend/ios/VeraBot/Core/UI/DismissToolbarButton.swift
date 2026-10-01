import SwiftUI

/// 工具栏 / sheet 里的「取消」「关闭」按钮：系统圆形 X（iOS 26 为 Liquid Glass 圆形按钮）。
/// 只用于 toolbar；确认框 / alert 里的取消仍用系统文字按钮。
struct DismissToolbarButton: View {
    enum Kind { case cancel, close }

    var kind: Kind = .cancel
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: kind == .close ? .close : .cancel, action: action) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(label)
        } else {
            Button(role: .cancel, action: action) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(label)
        }
    }

    private var label: String { kind == .close ? "关闭" : "取消" }
}
