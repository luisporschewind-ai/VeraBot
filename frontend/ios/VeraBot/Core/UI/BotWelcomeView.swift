import SwiftUI

/// Local characters only: welcoming the user never depends on a server or Bot account.
struct BotWelcomeGroup: View {
    var size: CGFloat = 100
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var greeted = -1

    var body: some View {
        HStack(alignment: .bottom, spacing: -8) {
            character(index: 0, color: .brandAccent, scale: 0.78, angle: -12, delay: 0)
            character(index: 1, color: .brandFill, scale: 1, angle: 0, delay: 0.12)
            character(index: 2, color: .brandFill, scale: 0.72, angle: 12, delay: 0.24)
        }
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background {
            Ellipse().fill(Color.brandSoft)
                .frame(width: size * 2.6, height: size * 0.95)
                .offset(y: 20)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { arrived = true }
        .task {
            guard !reduceMotion else { return }
            do {
                try await Task.sleep(for: .milliseconds(400))
                for index in 0..<3 {
                    greeted = index
                    try await Task.sleep(for: .milliseconds(200))
                }
            } catch { /* Hidden view cancels its greeting. */ }
        }
    }

    private func character(index: Int, color: Color, scale: CGFloat, angle: Double, delay: Double) -> some View {
        RobotAvatarView(action: reduceMotion ? .idle : (greeted >= index ? .send : .wake), size: size * scale,
                        roundness: index == 1 ? 0.7 : 0.35, color: color, ambient: !reduceMotion)
            .rotationEffect(.degrees(angle))
            .offset(y: arrived || reduceMotion ? 0 : 18)
            .opacity(arrived || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75).delay(delay), value: arrived)
    }
}

struct BotLaunchView: View {
    var body: some View {
        VStack(spacing: 20) {
            BotWelcomeGroup(size: 116)
            VStack(spacing: 8) {
                Text("Vera Bot").font(.largeTitle.bold()).foregroundStyle(Color.brandText)
                Text("嗨，我们在这儿。")
                    .font(.title3).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("launch.welcome")
    }
}
