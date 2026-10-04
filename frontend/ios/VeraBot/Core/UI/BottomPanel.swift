import SwiftUI

// MARK: - 自定义底部面板（Bottom panel）
//
// 圆角卡片从底部以弹簧动画弹起，默认约屏幕高度的 70%，背景变暗；点空白处或下拉顶部把手关闭。
// 用 fullScreenCover 承载，以盖住 Tab 栏；系统自带的上滑动画被关闭、背景设为透明，
// 弹起 / 收起动画全部由面板自己控制。用法：`.bottomPanel(isPresented: $show) { ... }`。

extension View {
    func bottomPanel<Panel: View>(isPresented: Binding<Bool>,
                                  heightFraction: CGFloat = 0.7,
                                  @ViewBuilder content: @escaping () -> Panel) -> some View {
        modifier(BottomPanelModifier(isPresented: isPresented, heightFraction: heightFraction, panel: content))
    }
}

private struct BottomPanelModifier<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let heightFraction: CGFloat
    let panel: () -> Panel
    @State private var coverShown = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $coverShown) {
                BottomPanelContainer(heightFraction: heightFraction,
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
    let heightFraction: CGFloat
    let onClosed: () -> Void
    let panel: () -> Panel

    @State private var shown = false
    @State private var dragOffset: CGFloat = 0
    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height * heightFraction
            ZStack(alignment: .bottom) {
                Color.black.opacity(shown ? 0.35 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityLabel("关闭")
                    .accessibilityAddTraits(.isButton)

                VStack(spacing: 0) {
                    // 顶部把手：下拉关闭只绑在把手区，避免与面板内列表滚动冲突
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                    panel()
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Color.appBackground)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 16, y: -2)
                .offset(y: shown ? dragOffset : height + 40)
            }
        }
        // 只忽略容器安全区：键盘弹出时（如调试页的服务器地址）面板随键盘上移，输入框不被挡住
        .ignoresSafeArea(.container)
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
