import SwiftUI
import UIKit

// MARK: - 键盘处理（Keyboard handling）：只用系统原生行为，不做自定义动画 / 手动偏移
//
// - 对话页：输入栏通过 bottomBar（iOS 26 safeAreaBar / 旧系统 safeAreaInset）随键盘上移；消息列表 defaultScrollAnchor(.bottom)，
//   键盘弹出（keyboardDidShow）与新消息时滚动到底部；scrollDismissesKeyboard(.interactively)；点空白处收起。
// - 表单：单行字段 @FocusState + submitLabel(.next)，回车跳到下一项；人设 / 指令为多行（回车换行）；键盘工具栏「完成」收起
//   （sheet 内的表单不用键盘工具栏：会让下层对话页的键盘避让错乱，改为 保存 / 关闭 / 下拉收起）。
// - 全局：离开页面、弹出 sheet、App 进入后台时收起键盘。

enum Keyboard {
    /// 收起当前键盘（任意第一响应者）
    @MainActor static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// 键盘工具栏的「完成」按钮（enabled = false 时不添加；sheet 内不要使用，见 BotEditView）
    @ViewBuilder func keyboardDoneButton(enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        if enabled {
            toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成", action: action).fontWeight(.semibold)
                }
            }
        } else {
            self
        }
    }

    /// 初次进入与视口尺寸变化（如键盘弹出）时滚动位置贴底；消息少时仍从顶部排列（不改变 alignment）
    @ViewBuilder func bottomAnchoredScrolling() -> some View {
        if #available(iOS 18.0, *) {
            self.defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
        } else {
            self
        }
    }

    /// App 离开前台（inactive / background）时收起键盘
    func dismissKeyboardOnBackground() -> some View {
        modifier(DismissKeyboardOnBackground())
    }
}

private struct DismissKeyboardOnBackground: ViewModifier {
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content.onChange(of: phase) { _, p in
            if p != .active { Keyboard.dismiss() }
        }
    }
}
