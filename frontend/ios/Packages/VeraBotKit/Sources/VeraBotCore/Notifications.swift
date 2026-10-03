import Foundation

public enum NotificationCategory: String, Codable, Sendable, Hashable {
    case reminder, bot_message, delegation, plugin, system, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NotificationCategory(rawValue: raw) ?? .unknown
    }

    public var title: String {
        switch self {
        case .reminder: "提醒"
        case .bot_message: "Bot 消息"
        case .delegation: "协作完成"
        case .plugin: "插件"
        case .system: "系统"
        case .unknown: "通知"
        }
    }

    public var systemImage: String {
        switch self {
        case .reminder: "alarm"
        case .bot_message: "person.crop.circle"
        case .delegation: "person.2"
        case .plugin: "puzzlepiece"
        case .system, .unknown: "gearshape"
        }
    }
}

public struct InboxNotification: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var category: NotificationCategory
    public var title: String
    public var body: String?
    public var sensitive: Bool
    public var link: String?
    public var threadId: String?
    public var botId: Int?
    public var reminderId: Int?
    public var messageId: Int?
    public var pluginId: String?
    public var createdAt: String?
    public var readAt: String?
    public var openedAt: String?

    public var isUnread: Bool { readAt == nil }

    enum CodingKeys: String, CodingKey {
        case body, sensitive, link
        case id = "id"
        case category = "category"
        case title = "title"
        case threadId = "thread_id"
        case botId = "bot_id"
        case reminderId = "reminder_id"
        case messageId = "message_id"
        case pluginId = "plugin_id"
        case createdAt = "created_at"
        case readAt = "read_at"
        case openedAt = "opened_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        if let raw = try c.decodeIfPresent(String.self, forKey: .category) {
            category = NotificationCategory(rawValue: raw) ?? .unknown
        } else {
            category = .unknown
        }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body)
        sensitive = try c.decodeIfPresent(Bool.self, forKey: .sensitive) ?? false
        link = try c.decodeIfPresent(String.self, forKey: .link)
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId)
        botId = try c.decodeIfPresent(Int.self, forKey: .botId)
        reminderId = try c.decodeIfPresent(Int.self, forKey: .reminderId)
        messageId = try c.decodeIfPresent(Int.self, forKey: .messageId)
        pluginId = try c.decodeIfPresent(String.self, forKey: .pluginId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
        openedAt = try c.decodeIfPresent(String.self, forKey: .openedAt)
    }
}

public struct NotificationsResponse: Codable, Sendable {
    public var notifications: [InboxNotification]
    public var unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case notifications
        case unreadCount = "unread_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try c.decodeIfPresent([InboxNotification].self, forKey: .notifications) ?? []
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }
}

public struct NotificationSummary: Codable, Sendable {
    public var unreadCount: Int
    public var byCategory: [String: Int]

    enum CodingKeys: String, CodingKey {
        case unreadCount = "unread_count"
        case byCategory = "by_category"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        byCategory = try c.decodeIfPresent([String: Int].self, forKey: .byCategory) ?? [:]
    }
}

public struct NotificationSettings: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var categories: [String: Bool]
    public var mutedBots: [Int]
    public var quietEnabled: Bool
    public var quietStart: String
    public var quietEnd: String
    public var quietTimeZone: String
    public var preview: String

    enum CodingKeys: String, CodingKey {
        case enabled = "enabled"
        case categories = "categories"
        case preview = "preview"
        case mutedBots = "muted_bots"
        case quietEnabled = "quiet_enabled"
        case quietStart = "quiet_start"
        case quietEnd = "quiet_end"
        case quietTimeZone = "quiet_timezone"
    }

    public init(enabled: Bool = true, categories: [String: Bool] = ["reminder": true, "bot_message": true, "delegation": true, "plugin": false, "system": true],
                mutedBots: [Int] = [], quietEnabled: Bool = false, quietStart: String = "23:00", quietEnd: String = "08:00",
                quietTimeZone: String = "Asia/Shanghai", preview: String = "title") {
        self.enabled = enabled
        self.categories = categories
        self.mutedBots = mutedBots
        self.quietEnabled = quietEnabled
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        self.quietTimeZone = quietTimeZone
        self.preview = preview
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = NotificationSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        categories = try c.decodeIfPresent([String: Bool].self, forKey: .categories) ?? fallback.categories
        mutedBots = try c.decodeIfPresent([Int].self, forKey: .mutedBots) ?? []
        quietEnabled = try c.decodeIfPresent(Bool.self, forKey: .quietEnabled) ?? false
        quietStart = try c.decodeIfPresent(String.self, forKey: .quietStart) ?? "23:00"
        quietEnd = try c.decodeIfPresent(String.self, forKey: .quietEnd) ?? "08:00"
        quietTimeZone = try c.decodeIfPresent(String.self, forKey: .quietTimeZone) ?? "Asia/Shanghai"
        preview = try c.decodeIfPresent(String.self, forKey: .preview) ?? "title"
    }
}

public struct DeviceRegistration: Codable, Sendable, Hashable {
    public var deviceId: String
    public var platform: String
    public var apnsToken: String?
    public var apnsEnv: String?
    public var appVersion: String?
    public var osVersion: String?
    public var timezone: String?
    public var localReminders: Bool

    enum CodingKeys: String, CodingKey {
        case platform = "platform"
        case timezone = "timezone"
        case deviceId = "device_id"
        case apnsToken = "apns_token"
        case apnsEnv = "apns_env"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case localReminders = "local_reminders"
    }

    public init(deviceId: String, platform: String = "ios", apnsToken: String? = nil, apnsEnv: String? = nil,
                appVersion: String? = nil, osVersion: String? = nil, timezone: String? = nil, localReminders: Bool = true) {
        self.deviceId = deviceId
        self.platform = platform
        self.apnsToken = apnsToken
        self.apnsEnv = apnsEnv
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.timezone = timezone
        self.localReminders = localReminders
    }
}

public enum DeviceIdentity {
    public static let storageKey = "vb_device_id"

    public static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: storageKey), !existing.isEmpty { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: storageKey)
        return created
    }

    @discardableResult
    public static func rotate(defaults: UserDefaults = .standard) -> String {
        defaults.removeObject(forKey: storageKey)
        return current(defaults: defaults)
    }
}

public struct PlannedNotification: Equatable, Sendable {
    public var identifier: String
    public var reminderID: Int
    public var userID: Int
    public var title: String
    public var fireDate: Date
    public var repeats: Bool
    public var weekday: Int?

    public init(identifier: String, reminderID: Int, userID: Int, title: String, fireDate: Date, repeats: Bool, weekday: Int? = nil) {
        self.identifier = identifier
        self.reminderID = reminderID
        self.userID = userID
        self.title = title
        self.fireDate = fireDate
        self.repeats = repeats
        self.weekday = weekday
    }
}

public struct ScheduledLocalNotification: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var repeats: Bool

    public init(identifier: String, title: String, repeats: Bool) {
        self.identifier = identifier
        self.title = title
        self.repeats = repeats
    }
}

public enum NotificationPlanner {
    public static let maxPending = 60
    public static let horizon: TimeInterval = 14 * 24 * 3600

    public static func plan(userID: Int, reminders: [Reminder], now: Date = Date(), preview: String = "title") -> [PlannedNotification] {
        var items: [PlannedNotification] = []
        for reminder in reminders where reminder.notify && [.scheduled, .due, .snoozed].contains(reminder.status) {
            let title = displayTitle(reminder, preview: preview)
            if reminder.status == .snoozed, let until = reminder.snoozedUntil, until > now {
                items.append(oneShot(userID: userID, reminder: reminder, title: title, fire: until))
                continue
            }
            if let kind = simpleKind(reminder.rrule), let anchor = reminder.dueUTC ?? reminder.nextFires.first {
                switch kind {
                case "daily":
                    items.append(repeating(userID: userID, reminder: reminder, title: title, fire: next(anchor, after: now), suffix: "daily", weekday: nil))
                case "weekly":
                    items.append(repeating(userID: userID, reminder: reminder, title: title, fire: next(anchor, after: now), suffix: "weekly", weekday: nil))
                case "weekdays":
                    for day in 1...5 {
                        let fire = nextWeekday(day, hour: anchor, after: now)
                        items.append(repeating(userID: userID, reminder: reminder, title: title, fire: fire, suffix: "wd.\(day)", weekday: day))
                    }
                default:
                    break
                }
            } else {
                for fire in reminder.nextFires where fire > now && fire <= now.addingTimeInterval(horizon) {
                    items.append(oneShot(userID: userID, reminder: reminder, title: title, fire: fire))
                }
            }
        }
        return Array(items.sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
            return lhs.identifier < rhs.identifier
        }.prefix(maxPending))
    }

    public static func reconcile(userID: Int, desired: [PlannedNotification], existing: [ScheduledLocalNotification]) -> (remove: [String], add: [PlannedNotification]) {
        let prefix = "vb.\(userID)."
        let wanted = Dictionary(uniqueKeysWithValues: desired.map { ($0.identifier, $0) })
        var remove: [String] = []
        for item in existing where item.identifier.hasPrefix(prefix) {
            if let match = wanted[item.identifier] {
                if match.title != item.title || match.repeats != item.repeats {
                    remove.append(item.identifier)
                }
            } else {
                remove.append(item.identifier)
            }
        }
        let gone = Set(remove)
        let present = Set(existing.map(\.identifier)).subtracting(gone)
        let add = desired.filter { !present.contains($0.identifier) }
        return (remove, add)
    }

    public static func displayTitle(_ reminder: Reminder, preview: String) -> String {
        if preview == "none" { return "你有一条新通知" }
        return reminder.title.isEmpty ? reminder.content : reminder.title
    }

    static func simpleKind(_ rule: String?) -> String? {
        guard let rule, !rule.isEmpty else { return nil }
        if rule.contains("COUNT=") || rule.contains("UNTIL=") { return nil }
        var parts: [String: String] = [:]
        for piece in rule.split(separator: ";") {
            let pair = piece.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { parts[String(pair[0])] = String(pair[1]) }
        }
        if let interval = parts["INTERVAL"], interval != "1" { return nil }
        if parts["FREQ"] == "DAILY", parts["BYDAY"] == nil, parts["BYMONTHDAY"] == nil { return "daily" }
        if parts["FREQ"] == "WEEKLY" {
            let days = parts["BYDAY"] ?? ""
            if days == "MO,TU,WE,TH,FR" { return "weekdays" }
            if ["MO", "TU", "WE", "TH", "FR", "SA", "SU"].contains(days) { return "weekly" }
        }
        return nil
    }

    private static func oneShot(userID: Int, reminder: Reminder, title: String, fire: Date) -> PlannedNotification {
        let epoch = Int(fire.timeIntervalSince1970)
        return PlannedNotification(identifier: "vb.\(userID).rem.\(reminder.id).\(epoch)", reminderID: reminder.id,
                                   userID: userID, title: title, fireDate: fire, repeats: false)
    }

    private static func repeating(userID: Int, reminder: Reminder, title: String, fire: Date, suffix: String, weekday: Int?) -> PlannedNotification {
        PlannedNotification(identifier: "vb.\(userID).rem.\(reminder.id).\(suffix)", reminderID: reminder.id,
                            userID: userID, title: title, fireDate: fire, repeats: true, weekday: weekday)
    }

    private static func next(_ anchor: Date, after now: Date) -> Date {
        anchor > now ? anchor : anchor.addingTimeInterval(24 * 3600)
    }

    private static func nextWeekday(_ day: Int, hour anchor: Date, after now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let hour = calendar.component(.hour, from: anchor)
        let minute = calendar.component(.minute, from: anchor)
        var cursor = calendar.startOfDay(for: now)
        for _ in 0..<8 {
            let weekday = calendar.component(.weekday, from: cursor)
            let mondayBased = weekday == 1 ? 7 : weekday - 1
            if mondayBased == day {
                var parts = calendar.dateComponents([.year, .month, .day], from: cursor)
                parts.hour = hour
                parts.minute = minute
                if let date = calendar.date(from: parts), date > now { return date }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return now.addingTimeInterval(3600)
    }
}

public enum DeepLink: Equatable, Sendable {
    case reminder(Int)
    case reminders(bucket: String?)
    case chat(botID: Int, messageID: Int?)
    case plugin(String)
    case inbox
    case notificationSettings
}

public enum DeepLinkResolution: Equatable, Sendable {
    case navigate(DeepLink)
    case missing
}

public enum DeepLinkRouter {
    public static func parse(_ raw: String) -> DeepLink {
        let pieces = raw.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(pieces.first ?? "")
        let query = queryItems(pieces.count > 1 ? String(pieces[1]) : "")
        if path == "inbox" { return .inbox }
        if path == "settings/notifications" { return .notificationSettings }
        if path == "reminders" { return .reminders(bucket: query["bucket"]) }
        if path.hasPrefix("reminder/"), let id = Int(path.dropFirst("reminder/".count)), id > 0 {
            return .reminder(id)
        }
        if path.hasPrefix("bot/"), path.contains("/chat") {
            let body = path.dropFirst("bot/".count)
            let idText = body.split(separator: "/").first.map(String.init) ?? ""
            if let id = Int(idText) {
                let message = query["message"].flatMap(Int.init)
                return .chat(botID: id, messageID: message)
            }
        }
        if path.hasPrefix("plugin/") {
            let id = String(path.dropFirst("plugin/".count))
            if !id.isEmpty { return .plugin(id) }
        }
        return .inbox
    }

    public static func resolve(_ raw: String, reminderIDs: Set<Int>, botIDs: Set<Int>, pluginIDs: Set<String>) -> DeepLinkResolution {
        switch parse(raw) {
        case .reminder(let id):
            return reminderIDs.contains(id) ? .navigate(.reminder(id)) : .missing
        case .chat(let botID, let messageID):
            return botIDs.contains(botID) ? .navigate(.chat(botID: botID, messageID: messageID)) : .missing
        case .plugin(let id):
            return pluginIDs.contains(id) ? .navigate(.plugin(id)) : .missing
        case let other:
            return .navigate(other)
        }
    }

    private static func queryItems(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        for piece in raw.split(separator: "&") where piece.contains("=") {
            let pair = piece.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { out[String(pair[0])] = String(pair[1]) }
        }
        return out
    }
}

public struct ReminderOutboxItem: Codable, Equatable, Sendable {
    public var idempotencyKey: String
    public var reminderID: Int
    public var action: String
    public var minutes: Int?
    public var until: String?

    public init(idempotencyKey: String, reminderID: Int, action: String, minutes: Int? = nil, until: String? = nil) {
        self.idempotencyKey = idempotencyKey
        self.reminderID = reminderID
        self.action = action
        self.minutes = minutes
        self.until = until
    }
}

public enum ReminderOutbox {
    public static func fileName(userID: Int) -> String { "outbox-\(userID).json" }

    public static func decode(_ data: Data) -> [ReminderOutboxItem] {
        (try? JSONDecoder().decode([ReminderOutboxItem].self, from: data)) ?? []
    }

    public static func encode(_ items: [ReminderOutboxItem]) -> Data {
        (try? JSONEncoder().encode(items)) ?? Data()
    }

    public static func appending(_ item: ReminderOutboxItem, to items: [ReminderOutboxItem]) -> [ReminderOutboxItem] {
        if items.contains(where: { $0.idempotencyKey == item.idempotencyKey }) { return items }
        return items + [item]
    }

    /// 409 视为已经处理（状态不允许，或别处改过），不再重放。
    public static func shouldDrop(status: Int, code: String?) -> Bool {
        status == 409 && (code == "invalid_transition" || code == "version_conflict")
    }
}

public struct ChatNotification: Decodable, Sendable, Hashable {
    public var id: Int
    public var category: String
    public var title: String
    public var link: String?

    public init(id: Int, category: String, title: String, link: String? = nil) {
        self.id = id
        self.category = category
        self.title = title
        self.link = link
    }
}
