import Foundation

/// 到点提醒在 App 前台时的展示方式。
public enum LocalNotificationPresentation: Equatable, Sendable {
    /// 交给系统展示横幅（声音按用户偏好）。
    case system(sound: Bool)
    /// 不弹系统通知，改由 App 内的 BotNotice 提示。
    case inApp
}

public enum LocalNotificationPolicy {
    /// 用户已经在 App 里时，提醒不再重复弹系统通知；其它通知保持原有系统横幅。
    public static func presentation(isForeground: Bool, isReminder: Bool, soundEnabled: Bool) -> LocalNotificationPresentation {
        if isForeground, isReminder { return .inApp }
        return .system(sound: soundEnabled)
    }
}

public struct ReminderLocalOverride: Codable, Sendable, Equatable {
    public var reminderID: Int
    public var action: String
    public var until: Date?
    public init(reminderID: Int, action: String, until: Date?) {
        self.reminderID = reminderID; self.action = action; self.until = until
    }
    public init(_ item: ReminderOutboxItem) {
        self.init(reminderID: item.reminderID, action: item.action, until: VeraBotDate.parse(item.until))
    }
}
