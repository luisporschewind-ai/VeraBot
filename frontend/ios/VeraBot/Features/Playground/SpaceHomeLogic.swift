import Foundation

/// 空间页 Bot 当前状态；优先级：旅行 > 任务 > 空闲。
enum SpaceBotActivity: Equatable, Sendable {
    case traveling(city: String)
    case onTask
    case idle

    var label: String {
        switch self {
        case .traveling(let city): "旅行中 · \(city)"
        case .onTask: "正在执行任务"
        case .idle: "空闲"
        }
    }
}

/// 「正在继续」至多一项：进行中的旅行优先，其次一个进行中的 Bot 任务。
enum SpaceContinueKind: Equatable, Sendable {
    case trip
    case task
}

enum SpaceHomeLogic {
    /// Bot 任务视为进行中：pending / running / needs_user（含 needsUser 标记）；done / failed 不算。
    static func isActiveBotTask(statusKey: String?, needsUser: Bool) -> Bool {
        if needsUser { return true }
        switch statusKey {
        case "pending", "running", "needs_user": return true
        default: return false
        }
    }

    static func activity(travelingCity: String?, hasActiveTask: Bool) -> SpaceBotActivity {
        if let city = travelingCity { return .traveling(city: city) }
        if hasActiveTask { return .onTask }
        return .idle
    }

    static func continueKind(hasActiveTrip: Bool, hasActiveTask: Bool) -> SpaceContinueKind? {
        if hasActiveTrip { return .trip }
        if hasActiveTask { return .task }
        return nil
    }
}
