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

/// 跟踪对话列表「用户是否正在滚动」。
///
/// 不能只靠底部锚点的几何变化判断贴底：流式回答变长、图片加载、LazyVStack 行高修正都会把锚点推出视口，
/// 若把「跟着新内容」误判成「用户滚离底部」，回复过程中就不会再自动滚动，直到用户点「回到最新」。
/// 因此贴底意图只由用户主动滚动改变：iOS 18+ 用系统滚动阶段，iOS 17 用拖拽手势兜底。
struct ChatScrollInteraction: ViewModifier {
    /// true = 用户开始/正在滚动；false = 滚动已停稳，可以结算最终的贴底状态。
    let onChange: (Bool) -> Void
    @State private var settleTask: Task<Void, Never>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                switch phase {
                case .tracking, .interacting, .decelerating:
                    onChange(true)
                case .idle:
                    onChange(false)
                case .animating:
                    // 程序化滚动（回到最新、键盘调整、初始定位）不是用户滚动，不能据此取消跟随。
                    break
                @unknown default:
                    break
                }
            }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in onChange(true) }
                    .onEnded { _ in
                        // 松手后还有惯性减速：稍等再结算，避免用减速中的位置误判贴底。
                        settleTask?.cancel()
                        settleTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            onChange(false)
                        }
                    }
            )
        }
    }
}
