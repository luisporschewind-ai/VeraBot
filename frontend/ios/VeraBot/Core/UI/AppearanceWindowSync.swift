import SwiftUI
import UIKit

/// preferredColorScheme updates the hosting presentation but can leave an already
/// presented sheet with its old traits. Apply the preference to this scene's window
/// so SwiftUI, sheets, alerts and UIKit controllers inherit the same live appearance.
struct AppearanceWindowSync: UIViewRepresentable {
    let mode: AppearanceMode

    func makeUIView(context: Context) -> AppearanceAnchor {
        let view = AppearanceAnchor()
        view.isUserInteractionEnabled = false
        view.mode = mode
        return view
    }

    func updateUIView(_ view: AppearanceAnchor, context: Context) {
        view.mode = mode
    }

    final class AppearanceAnchor: UIView {
        var mode: AppearanceMode = .system { didSet { apply() } }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            let style: UIUserInterfaceStyle = switch mode {
            case .system: .unspecified
            case .light: .light
            case .dark: .dark
            }
            if let window, window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
