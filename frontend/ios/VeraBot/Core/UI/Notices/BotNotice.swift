import Foundation
import Observation

enum BotNoticeTone: String, CaseIterable, Identifiable {
    case information, success, warning, failure, progress, confirmation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .information: "告知"
        case .success: "完成"
        case .warning: "留意"
        case .failure: "未完成"
        case .progress: "进行中"
        case .confirmation: "待确认"
        }
    }
    var avatar: BotAvatarState {
        switch self {
        case .information: .idle
        case .success: .success
        case .warning: .warning
        case .failure: .failure
        case .progress: .working
        case .confirmation: .awaitingConfirmation
        }
    }
}

/// Content has no business closures. The owning page handles the optional action by ID.
struct BotNotice: Equatable {
    var title: String
    var detail = ""
    var tone: BotNoticeTone = .information
    var avatar: BotAvatarState = .idle
    var actionTitle: String? = nil
    var duration: Double? = 3
    var link: String? = nil
}

@MainActor @Observable
final class BotNoticeCenter {
    private var queue = NoticeQueue<BotNotice>()
    var current: NoticeQueue<BotNotice>.Entry? { queue.current }
    var pendingCount: Int { queue.pending.count }

    func show(_ notice: BotNotice, key: String, replacing: Bool = false) {
        queue.show(notice, key: key, replacing: replacing)
    }
    func dismiss(id: UUID) { queue.dismiss(id: id) }
    func clear() { queue.clear() }
}
