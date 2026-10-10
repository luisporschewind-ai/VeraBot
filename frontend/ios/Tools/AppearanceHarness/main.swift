import SwiftUI
import UIKit

// Exercise actual native presentations with the production window synchronizer.
// The legacy variant reproduces: open a sheet in light, change to dark, sheet stays light.
@MainActor @Observable private final class ProbeState {
    var mode: AppearanceMode = .light
    var sheet = false
    var cover = false
    var alert = false
    var started = false
    var failures: [String] = []
    var checks = 0
}

@main private struct AppearanceProbe: App {
    @State private var state = ProbeState()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 24) {
                Text("Vera Bot appearance regression").font(.headline)
                TextField("Retained input", text: .constant("keep this input"))
                    .themedFieldBackground()
                RoundedRectangle(cornerRadius: 24).fill(Color.sectionFill).frame(height: 180)
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            #if LEGACY_APPEARANCE
            .preferredColorScheme(state.mode.colorScheme)
            #else
            .background(AppearanceWindowSync(mode: state.mode))
            #endif
            .sheet(isPresented: $state.sheet) { panel("Sheet") }
            .fullScreenCover(isPresented: $state.cover) { panel("Full screen") }
            .alert("Appearance alert", isPresented: $state.alert) { Button("OK") {} }
            .onAppear {
                guard !state.started else { return }
                state.started = true
                Task { await run() }
            }
        }
    }

    private func panel(_ title: String) -> some View {
        VStack(spacing: 24) {
            Text(title).font(.title)
            RoundedRectangle(cornerRadius: 24).fill(Color.sectionFill).frame(height: 180)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(900)) }

    private func run() async {
        await settle()
        record("initial-light", expected: 1, presented: false)
        let defaults = UserDefaults.standard
        let previousAppearance = defaults.object(forKey: "vb_appearance")
        defaults.set("native", forKey: "vb_appearance")
        state.mode = .native
        await settle()
        recordNativePalette()
        record("native-light", expected: 1, presented: false)
        if let previousAppearance { defaults.set(previousAppearance, forKey: "vb_appearance") }
        else { defaults.removeObject(forKey: "vb_appearance") }
        state.mode = .light
        await settle()
        state.sheet = true
        await settle()
        state.mode = .dark
        await settle()
        record("dark-sheet", expected: 2, presented: true)
        state.mode = .light
        await settle()
        record("light-sheet", expected: 1, presented: true)
        state.sheet = false
        await settle()
        record("light-dismissed", expected: 1, presented: false)
        state.cover = true
        await settle()
        state.mode = .dark
        await settle()
        record("dark-cover", expected: 2, presented: true)
        state.cover = false
        await settle()
        record("dark-return", expected: 2, presented: false)
        state.alert = true
        await settle()
        state.mode = .light
        await settle()
        record("light-alert", expected: 1, presented: true)
        state.alert = false
        state.mode = .system
        await settle()
        record("system", expected: ProcessInfo.processInfo.arguments.contains("--system-dark") ? 2 : 1, presented: false)
        let report = "checks=\(state.checks) failures=\(state.failures.count)\n" + state.failures.joined(separator: "\n")
        try? report.write(to: output("report.txt"), atomically: true, encoding: .utf8)
    }

    private func recordNativePalette() {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let palette: [(String, Color, UIColor)] = [
            ("background", .appBackground, .systemBackground),
            ("section", .sectionFill, .secondarySystemBackground),
            ("brand-text", .brandText, .label),
            ("brand", .brand, .systemBlue)
        ]
        var problems: [String] = []
        for (name, color, expected) in palette where !matches(UIColor(color), expected, traits: traits) {
            problems.append(name)
        }
        state.checks += 1
        let passed = problems.isEmpty
        let text = "native-palette: \(passed ? "PASS" : "FAIL") mismatched=\(problems.joined(separator: ","))\n"
        if !passed { state.failures.append(text) }
        try? text.write(to: output("native-palette.txt"), atomically: true, encoding: .utf8)
    }

    private func matches(_ actual: UIColor, _ expected: UIColor, traits: UITraitCollection) -> Bool {
        var actualRed: CGFloat = 0, actualGreen: CGFloat = 0, actualBlue: CGFloat = 0, actualAlpha: CGFloat = 0
        var expectedRed: CGFloat = 0, expectedGreen: CGFloat = 0, expectedBlue: CGFloat = 0, expectedAlpha: CGFloat = 0
        guard actual.resolvedColor(with: traits).getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha),
              expected.resolvedColor(with: traits).getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha) else { return false }
        return abs(actualRed - expectedRed) < 0.005 && abs(actualGreen - expectedGreen) < 0.005 &&
            abs(actualBlue - expectedBlue) < 0.005 && abs(actualAlpha - expectedAlpha) < 0.005
    }

    private func output(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }

    private func record(_ name: String, expected: Int, presented: Bool) {
        state.checks += 1
        let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first
        let root = window?.rootViewController
        let windowStyle = window?.traitCollection.userInterfaceStyle.rawValue ?? -1
        let rootStyle = root?.traitCollection.userInterfaceStyle.rawValue ?? -1
        let presentedStyle = root?.presentedViewController?.traitCollection.userInterfaceStyle.rawValue ?? -1
        let passed = windowStyle == expected && rootStyle == expected && (!presented || presentedStyle == expected)
        let text = "\(name): \(passed ? "PASS" : "FAIL") expected=\(expected) window=\(windowStyle) root=\(rootStyle) presented=\(presentedStyle)\n"
        if !passed { state.failures.append(text) }
        try? text.write(to: output("\(name).txt"), atomically: true, encoding: .utf8)
        if let window {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try? image.pngData()?.write(to: output("\(name).png"))
        }
    }
}
