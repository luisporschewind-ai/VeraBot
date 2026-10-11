import SwiftUI

enum BotNoticeSurface: String, CaseIterable, Identifiable {
    case quiet, material, liquidGlass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quiet: "柔和实底"
        case .material: "轻透材质"
        case .liquidGlass: "液态玻璃"
        }
    }
}

struct BotNoticeStyle: Equatable {
    var surface: BotNoticeSurface = .quiet
    var botSize: Double = 40
    var cornerRadius: Double = 22
    var motionDuration: Double = 0.32
    var reduceMotion = false
    var haptics = false
    var appearance: BotNoticeAppearance = .system
}

enum BotNoticeAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "跟随页面"; case .light: "浅色"; case .dark: "深色" }
    }
    func resolve(_ page: ColorScheme) -> ColorScheme {
        switch self { case .system: page; case .light: .light; case .dark: .dark }
    }
}

/// Shared visual for a transient banner, an inline status and a lab preview.
struct BotNoticeCard: View {
    let notice: BotNotice
    var style = BotNoticeStyle()
    var replay = 0
    var action: (() -> Void)? = nil
    var dismiss: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var pageScheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BotNoticeAvatar(action: notice.avatar, size: style.botSize, replay: replay,
                            reduced: systemReduceMotion || style.reduceMotion)
                .frame(width: style.botSize + 4, height: style.botSize + 8)
                .allowsHitTesting(false).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title).font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                if !notice.detail.isEmpty {
                    Text(notice.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if typeSize.isAccessibilitySize { actionButton }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize { actionButton }
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").font(.caption.weight(.medium)) }
                    .foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("关闭提示")
            }
        }
        .padding(.leading, 14).padding(.trailing, dismiss == nil ? 16 : 4).padding(.vertical, 10)
        .modifier(BotNoticeSurfaceModifier(style: style))
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.tone.title)
        .environment(\.colorScheme, style.appearance.resolve(pageScheme))
    }

    @ViewBuilder private var actionButton: some View {
        if let title = notice.actionTitle, let action {
            Button(title, action: action).font(.caption.weight(.semibold))
                .foregroundStyle(Color.brand).frame(minHeight: 44)
        }
    }
}

private struct BotNoticeSurfaceModifier: ViewModifier {
    let style: BotNoticeStyle
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
    }

    @ViewBuilder func body(content: Content) -> some View {
        if style.surface == .liquidGlass, #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background {
                    if style.surface == .quiet { shape.fill(Color.sectionFill) }
                    else { shape.fill(.regularMaterial) }
                }
                .overlay { shape.strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
    }
}

/// A small notice expresses its state once, then rests on the existing representative pose.
/// The shared avatar's normal animation clock need not keep running for a retained status card.
private struct BotNoticeAvatar: View {
    let action: BotAvatarState
    let size: Double
    let replay: Int
    let reduced: Bool
    @State private var settled = false

    private var still: Bool { reduced || settled || action == .idle }
    private var key: String { "\(action.rawValue)|\(replay)|\(reduced)" }

    var body: some View {
        RobotAvatarView(action: action, size: size, color: .brandFill, ambient: false,
                        replay: replay, staticPreview: still, motionReduced: still)
            .task(id: key) {
                settled = false
                guard !reduced, action != .idle else { return }
                let length = RobotAvatarMotion.duration(action)
                do { try await Task.sleep(for: .milliseconds(length.isFinite ? length + 200 : 4800)) }
                catch { return }
                guard !Task.isCancelled else { return }
                settled = true
            }
    }
}

/// Attach to the current presentation surface; sheets/covers own a separate scoped center.
private struct BotNoticeHost: ViewModifier {
    let center: BotNoticeCenter
    let style: BotNoticeStyle
    let action: (NoticeQueue<BotNotice>.Entry) -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var drag: CGFloat = 0
    @State private var successTick = 0
    @State private var warningTick = 0

    private var reduced: Bool { systemReduceMotion || style.reduceMotion }

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let entry = center.current {
                BotNoticeCard(notice: entry.message, style: style,
                              action: { action(entry) }, dismiss: { center.dismiss(id: entry.id) })
                    .padding(.horizontal, 16).padding(.top, 8)
                    .frame(maxWidth: 560)
                    .offset(y: min(0, drag))
                    .gesture(DragGesture(minimumDistance: 12)
                        .updating($drag) { value, state, _ in state = min(0, value.translation.height) }
                        .onEnded { value in
                            if value.translation.height < -28 { center.dismiss(id: entry.id) }
                        })
                    .id(entry.id)
                    .transition(reduced ? .opacity : .offset(y: -16).combined(with: .opacity))
                    .accessibilityIdentifier("notice.banner")
                    .task(id: entry.id) {
                        AccessibilityNotification.Announcement(
                            entry.message.title + (entry.message.detail.isEmpty ? "" : "，" + entry.message.detail)
                        ).post()
                        // VoiceOver keeps the card until explicit dismissal so its action remains reachable.
                        guard !voiceOver, let seconds = entry.message.duration else { return }
                        do { try await Task.sleep(for: .seconds(max(1, seconds))) }
                        catch { return }
                        guard !Task.isCancelled else { return }
                        center.dismiss(id: entry.id)
                    }
            }
        }
        .animation(reduced ? .easeOut(duration: 0.16) : .smooth(duration: style.motionDuration), value: center.current?.id)
        .hapticFeedback(.success, trigger: successTick)
        .hapticFeedback(.warning, trigger: warningTick)
        .onChange(of: center.current?.id) { _, id in
            guard id != nil, style.haptics else { return }
            switch center.current?.message.tone {
            case .success: successTick += 1
            case .warning, .failure: warningTick += 1
            default: break
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { center.clear() } }
        .onDisappear { center.clear() }
    }
}

extension View {
    func botNoticeHost(_ center: BotNoticeCenter, style: BotNoticeStyle = .init(),
                       action: @escaping (NoticeQueue<BotNotice>.Entry) -> Void = { _ in }) -> some View {
        modifier(BotNoticeHost(center: center, style: style, action: action))
    }
}
