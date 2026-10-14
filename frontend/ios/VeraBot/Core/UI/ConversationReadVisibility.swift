import SwiftUI
import VeraBotCore

struct ConversationViewportKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
struct ConversationComposerKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
struct ConversationBottomKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

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
extension View {
    func conversationComposer(_ rect: Binding<CGRect>) -> some View {
        background(GeometryReader { geometry in Color.clear.preference(key: ConversationComposerKey.self, value: geometry.frame(in: .global)) })
            .onPreferenceChange(ConversationComposerKey.self) { rect.wrappedValue = $0 }
    }
    func conversationViewport(_ rect: Binding<CGRect>) -> some View {
        background(GeometryReader { geometry in Color.clear.preference(key: ConversationViewportKey.self, value: geometry.frame(in: .global)) })
            .onPreferenceChange(ConversationViewportKey.self) { rect.wrappedValue = $0 }
    }
    func conversationReadVisibility(viewport: CGRect, enabled: Bool, revision: Int, onRead: @escaping () async -> Void) -> some View {
        modifier(ConversationReadVisibility(viewport: viewport, enabled: enabled, revision: revision, onRead: onRead))
    }
}
