import SafariServices
import SwiftUI
import VeraBotCore

/// App 内浏览器：接管当前视图树的 openURL（OpenURLAction）。
/// http / https → 全屏 SFSafariViewController（系统原生，带「完成」/ 分享 / 在 Safari 中打开）；
/// tel: / mailto: 等其他链接 → .systemAction 交给系统（电话 / 邮件）。
extension View {
    func inAppBrowser() -> some View { modifier(InAppBrowserModifier()) }
}

private struct InAppBrowserModifier: ViewModifier {
    @State private var page: BrowserPage?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.opensInAppBrowser else { return .systemAction }
                page = BrowserPage(url: url)
                return .handled
            })
            .fullScreenCover(item: $page) { p in
                SafariView(url: p.url) { page = nil }
                    .ignoresSafeArea()
            }
    }
}

private struct BrowserPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// SFSafariViewController 的最小 SwiftUI 包装
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Color.brand)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onFinish() }
    }
}
