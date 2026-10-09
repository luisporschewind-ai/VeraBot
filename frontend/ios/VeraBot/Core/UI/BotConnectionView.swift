import SwiftUI
import VeraBotNetworking

extension ConnectionIssue {
    /// Use the existing avatar vocabulary; an outage is distinct from a failed task.
    var botAction: BotAvatarState {
        switch self {
        case .offline, .timedOut: .warning
        case .unreachable, .serviceUnavailable: .error
        }
    }
}

/// The same local Bot accompanies first-load fallback, retained-list banners and auth errors.
struct BotConnectionView: View {
    let issue: ConnectionIssue
    var retrying = false
    var compact = false
    let retry: () -> Void
    @State private var showDebug = false

    private var action: BotAvatarState { retrying ? .waiting : issue.botAction }

    var body: some View {
        Group {
            if compact {
                HStack(alignment: .center, spacing: 14) {
                    avatar(size: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(retrying ? "正在重新连接…" : issue.title).font(.subheadline.weight(.semibold))
                        Text(issue.message).font(.caption).foregroundStyle(.secondary)
                        Button(retrying ? "连接中…" : "重新连接", action: retry)
                            .font(.subheadline.weight(.semibold)).disabled(retrying)
                    }
                    Spacer(minLength: 0)
                    debugButton
                }
                .padding(16)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(spacing: 22) {
                    avatar(size: 132)
                        .padding(24)
                        .background(Color.brandSoft, in: Circle())
                    VStack(spacing: 10) {
                        Text(retrying ? "正在重新连接…" : issue.title)
                            .font(.title2.bold()).foregroundStyle(Color.brandText)
                        Text(issue.message).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button(action: retry) {
                        HStack(spacing: 8) {
                            if retrying { ProgressView().tint(.white) }
                            Text(retrying ? "连接中…" : "重新连接")
                        }
                        .padding(.horizontal, 18)
                    }
                    .prominentButtonStyle().controlSize(.large)
                    .allowsHitTesting(!retrying)
                    debugButton
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            }
        }
        .accessibilityIdentifier("connection.\(issue.rawValue)")
        .sheet(isPresented: $showDebug) {
            NavigationStack {
                DebugView()
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        DismissToolbarButton(kind: .close) { showDebug = false }
                    } }
            }
        }
    }

    private func avatar(size: CGFloat) -> some View {
        RobotAvatarView(action: action, size: size, color: .brandFill)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var debugButton: some View {
        Button { showDebug = true } label: { Image(systemName: "ladybug") }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("调试")
            .disabled(retrying)
    }
}

struct BotLoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            RobotAvatarView(action: .waiting, size: 110, color: .brandFill)
                .allowsHitTesting(false).accessibilityHidden(true)
            Text("正在连接你的 Bot…").foregroundStyle(.secondary)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .accessibilityIdentifier("connection.loading")
    }
}
