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

/// One inline notice for a screen that could not load, or for a pending action that is waiting on the network.
/// Load failures use the same title and button. A pending sentence keeps its own wording in this card.
struct ConnectionNotice: View {
    var title: String = "暂时连接不上"
    var message: String? = nil
    var retrying = false
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RobotAvatarView(action: retrying ? .waiting : .warning, size: 40, color: .brandFill)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(retrying ? "正在重新连接…" : title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button(retrying ? "连接中…" : "重新连接", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .disabled(retrying)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connection.notice")
    }
}

/// What a page should show in its single notice slot.
struct PageNotice: Equatable {
    var offline = false
    var title: String?
    var detail: String?
    var allowsRetry = false

    static func fromLoad(_ error: Error, message: String) -> PageNotice {
        if UserFacingError.isTransport(error) || message == UserFacingError.offline {
            return PageNotice(offline: true, allowsRetry: true)
        }
        return PageNotice(title: message, allowsRetry: true)
    }

    static func fromAction(_ error: Error, message: String) -> PageNotice {
        if UserFacingError.isTransport(error) || message == UserFacingError.offline {
            return PageNotice(offline: true, allowsRetry: true)
        }
        return PageNotice(title: message)
    }

    static func sentence(_ text: String) -> PageNotice {
        PageNotice(title: text)
    }
}

struct PageConnectionNotice: View {
    let notice: PageNotice
    var retrying = false
    let retry: () -> Void

    var body: some View {
        if notice.offline {
            ConnectionNotice(message: notice.detail, retrying: retrying, retry: retry)
        } else if let title = notice.title {
            ConnectionNotice(title: title, message: notice.detail, retry: notice.allowsRetry ? retry : nil)
        }
    }
}

extension View {
    /// List row for an inline connection notice: the card supplies its own fill.
    func connectionNoticeRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}
