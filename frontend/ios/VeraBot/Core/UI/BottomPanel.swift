import SwiftUI

// MARK: - 自定义底部面板（Bottom panel）
//
// 悬浮圆角卡片（四角 36、距左右下边 8pt）从底部以弹簧动画弹起，顶端停在首页导航栏下方
// （topInset，默认 52pt，导航栏一行仍露出并变暗），背景变暗；点空白处、下拉顶部把手或面板内
// 关闭按钮（环境值 `dismissBottomPanel`）关闭。用 fullScreenCover 承载，以盖住 Tab 栏；系统自带的上滑动画被关闭、背景设为透明，
// 弹起 / 收起动画全部由面板自己控制。用法：`.bottomPanel(isPresented: $show) { ... }`。

extension View {
    func bottomPanel<Panel: View>(isPresented: Binding<Bool>,
                                  topInset: CGFloat = 52,
                                  @ViewBuilder content: @escaping () -> Panel) -> some View {
        modifier(BottomPanelModifier(isPresented: isPresented, topInset: topInset, panel: content))
    }
}

private struct BottomPanelModifier<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let topInset: CGFloat
    let panel: () -> Panel
    @State private var coverShown = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $coverShown) {
                BottomPanelContainer(topInset: topInset,
                                     onClosed: { setCover(false); isPresented = false },
                                     panel: panel)
                    .presentationBackground(.clear)
            }
            .onChange(of: isPresented) { _, presented in
                if presented != coverShown { setCover(presented) }
            }
    }

    /// 不带系统动画地显示 / 移除承载层（动画由面板自己做）。
    private func setCover(_ shown: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { coverShown = shown }
    }
}

private struct BottomPanelContainer<Panel: View>: View {
    let topInset: CGFloat
    let onClosed: () -> Void
    let panel: () -> Panel

    @State private var shown = false
    @State private var dragOffset: CGFloat = 0
    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    var body: some View {
        GeometryReader { geo in
            // geo：顶部守安全区、底部到屏幕边（见下方 ignoresSafeArea），键盘弹出时随键盘缩短
            let height = max(geo.size.height - topInset - 8, 200)
            ZStack(alignment: .bottom) {
                Color.black.opacity(shown ? 0.35 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityLabel("关闭")
                    .accessibilityAddTraits(.isButton)

                panel()
                    .environment(\.dismissBottomPanel, close)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(Color.appBackground)
                    .overlay(alignment: .top) {
                        // 顶部居中把手：下拉关闭只绑在这一窄条，不挡导航栏左右按钮，也不与列表滚动冲突
                        Capsule()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 36, height: 5)
                            .padding(.top, 6)
                            .frame(width: 160, height: 30, alignment: .top)
                            .contentShape(Rectangle())
                            .gesture(dragGesture)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .offset(y: shown ? dragOffset : height + 60)
            }
        }
        // 只让底部伸到屏幕边（卡片自己留 8pt）；键盘安全区仍生效，调试页输入框不被挡住
        .ignoresSafeArea(.container, edges: .bottom)
        .accessibilityAction(.escape) { close() }   // VoiceOver 双指 Z 手势关闭
        .onAppear { withAnimation(spring) { shown = true } }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = max($0.translation.height, 0) }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 260 {
                    close()
                } else {
                    withAnimation(spring) { dragOffset = 0 }
                }
            }
    }

    private func close() {
        guard shown else { return }   // 收起动画进行中再点 / 再拖不重复触发
        withAnimation(spring, completionCriteria: .logicallyComplete) {
            shown = false
        } completion: {
            dragOffset = 0
            onClosed()
        }
    }
}

private struct DismissBottomPanelKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// 面板内的关闭动作（带收起动画）；不在 bottomPanel 里时为 nil。
    var dismissBottomPanel: (() -> Void)? {
        get { self[DismissBottomPanelKey.self] }
        set { self[DismissBottomPanelKey.self] = newValue }
    }
}

/// 面板左上角的圆形关闭按钮（浅灰圆底 + xmark）。
struct BottomPanelCloseButton: View {
    @Environment(\.dismissBottomPanel) private var dismiss
    var body: some View {
        if let dismiss {
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(.systemGray5)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
    }
}
