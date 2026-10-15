import SwiftUI
import VeraBotCore

/// Measures rendered content against the actual scroll viewport. Lazy prefetch is never proof of reading.
private struct ConversationReadVisibility: ViewModifier {
    let viewport: CGRect
    let enabled: Bool
    let revision: Int
    let onRead: () async -> Void
    @State private var frame: CGRect = .zero
    @State private var acknowledgedRevision = 0
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.onAppear { frame = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { _, value in frame = value }
        })
        .task(id: "\(enabled)|\(revision)|\(frame)|\(viewport)") {
            guard enabled, revision > 0, revision > acknowledgedRevision else { return }
            let intersection = frame.intersection(viewport)
            guard !intersection.isNull, ConversationVisibilityPolicy.isVisible(bodyHeight: frame.height, viewportHeight: viewport.height, intersectionHeight: intersection.height) else { return }
            // Modal covers can originate within message cards, outside this page's sheet bindings.
            func covered() -> Bool {
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController?.presentedViewController != nil
            }
            var dwell = 0
            while dwell < 5 {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard !Task.isCancelled, enabled, UIApplication.shared.applicationState == .active else { return }
                if covered() { dwell = 0 } else { dwell += 1 }
            }
            await onRead()
            if !Task.isCancelled { acknowledgedRevision = revision }
        }
    }
}
// Not a PreferenceKey: a `value = nextValue()` reduce lets sibling subtrees that never set the key
// overwrite the measured frame with `.zero`, so the viewport always read as empty.
extension View {
    func conversationComposer(_ rect: Binding<CGRect>) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect.wrappedValue = $0 }
    }
    func conversationViewport(_ rect: Binding<CGRect>) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect.wrappedValue = $0 }
    }
    /// The anchor must sit outside any LazyVStack: lazy rows stop reporting geometry once scrolled far away.
    func conversationBottomAnchor(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: action)
    }
    func conversationReadVisibility(viewport: CGRect, enabled: Bool, revision: Int, onRead: @escaping () async -> Void) -> some View {
        modifier(ConversationReadVisibility(viewport: viewport, enabled: enabled, revision: revision, onRead: onRead))
    }
}
