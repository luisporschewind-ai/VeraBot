import Foundation
import CryptoKit

public enum NotificationCategory: String, Codable, Sendable, Hashable {
    case reminder, bot_message, task_result, delegation, plugin, system, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NotificationCategory(rawValue: raw) ?? .unknown
    }

    public var title: String {
        switch self {
        case .reminder: "提醒"
        case .bot_message: "Bot 消息"
        case .task_result: "任务结果"
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
        case .task_result: "checklist"
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

    public var logicalKey: String?
    public var sourceKind: String?
    public var sourceState: String?
    public var sourceID: String?
    public var suppressionReason: String?
    public var expiresAt: String?

    public var isUnread: Bool { readAt == nil }

    enum CodingKeys: String, CodingKey {
        case logicalKey = "logical_key", sourceKind = "source_kind", sourceID = "source_id"
        case sourceState = "source_state"
        case suppressionReason = "suppression_reason", expiresAt = "expires_at"
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
        logicalKey = try c.decodeIfPresent(String.self, forKey: .logicalKey)
        sourceKind = try c.decodeIfPresent(String.self, forKey: .sourceKind)
        sourceState = try c.decodeIfPresent(String.self, forKey: .sourceState)
        sourceID = try c.decodeIfPresent(String.self, forKey: .sourceID)
        suppressionReason = try c.decodeIfPresent(String.self, forKey: .suppressionReason)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
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
    public var pendingActionCount: Int

    enum CodingKeys: String, CodingKey {
        case unreadCount = "unread_count"
        case byCategory = "by_category"
        case pendingActionCount = "pending_action_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        pendingActionCount = try c.decodeIfPresent(Int.self, forKey: .pendingActionCount) ?? 0
        byCategory = try c.decodeIfPresent([String: Int].self, forKey: .byCategory) ?? [:]
    }
}

public struct NotificationSettings: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var soundEnabled: Bool
    public var categories: [String: Bool]
    public var mutedBots: [Int]
    public var quietEnabled: Bool
    public var quietStart: String
    public var quietEnd: String
    public var quietTimeZone: String
    public var preview: String

    enum CodingKeys: String, CodingKey {
        case soundEnabled = "sound_enabled"
        case enabled = "enabled"
        case categories = "categories"
        case preview = "preview"
        case mutedBots = "muted_bots"
        case quietEnabled = "quiet_enabled"
        case quietStart = "quiet_start"
        case quietEnd = "quiet_end"
        case quietTimeZone = "quiet_timezone"
    }

    public init(enabled: Bool = true, categories: [String: Bool] = ["reminder": true, "bot_message": true, "task_result": true, "delegation": true, "plugin": false, "system": true],
                mutedBots: [Int] = [], quietEnabled: Bool = false, quietStart: String = "23:00", quietEnd: String = "08:00",
                quietTimeZone: String = "Asia/Shanghai", preview: String = "title", soundEnabled: Bool = true) {
        self.enabled = enabled
        self.soundEnabled = soundEnabled
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
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
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
    public var localEvents: Bool?

    enum CodingKeys: String, CodingKey {
        case platform = "platform"
        case timezone = "timezone"
        case deviceId = "device_id"
        case apnsToken = "apns_token"
        case apnsEnv = "apns_env"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case localReminders = "local_reminders"
        case localEvents = "local_events"
    }

    public init(deviceId: String, platform: String = "ios", apnsToken: String? = nil, apnsEnv: String? = nil,
                appVersion: String? = nil, osVersion: String? = nil, timezone: String? = nil, localReminders: Bool = true, localEvents: Bool = false) {
        self.deviceId = deviceId
        self.platform = platform
        self.apnsToken = apnsToken
        self.apnsEnv = apnsEnv
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.timezone = timezone
        self.localReminders = localReminders
        self.localEvents = localEvents
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
    public var timeZone: String
    public var soundEnabled = true
    public var signature: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        let timing = repeats ? "\(calendar.component(.hour, from: fireDate)):\(calendar.component(.minute, from: fireDate)):\(weekday ?? 0):\(timeZone)" : "\(Int(fireDate.timeIntervalSince1970))"
        return "\(title)|\(repeats)|\(timing)|reminder/\(reminderID)|sound:\(soundEnabled)"
    }

    public init(identifier: String, reminderID: Int, userID: Int, title: String, fireDate: Date, repeats: Bool, weekday: Int? = nil, timeZone: String = "Asia/Shanghai") {
        self.identifier = identifier
        self.reminderID = reminderID
        self.userID = userID
        self.title = title
        self.fireDate = fireDate
        self.repeats = repeats
        self.weekday = weekday
        self.timeZone = timeZone
    }
}

public struct ScheduledLocalNotification: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var repeats: Bool
    public var signature: String?

    public init(identifier: String, title: String, repeats: Bool, signature: String? = nil) {
        self.identifier = identifier
        self.title = title
        self.repeats = repeats
        self.signature = signature
    }
}

public enum NotificationPlanner {
    public static let maxPending = 60
    public static let horizon: TimeInterval = 14 * 24 * 3600

    public static func plan(userID: Int, reminders: [Reminder], now: Date = Date(), preview: String = "title",
                            settings: NotificationSettings = NotificationSettings(), overrides: [ReminderLocalOverride] = []) -> [PlannedNotification] {
        guard settings.enabled, settings.categories["reminder"] == true else { return [] }
        var items: [PlannedNotification] = []
        for reminder in reminders where reminder.notify && [.scheduled, .due, .snoozed].contains(reminder.status) {
            let botID = reminder.assigneeBotId ?? reminder.sourceBotId
            if reminder.createdBy != "user", let botID, settings.mutedBots.contains(botID) { continue }
            let title = displayTitle(reminder, preview: preview)
            if let local = overrides.last(where: { $0.reminderID == reminder.id }) {
                if local.action == "snooze", let until = local.until, until > now {
                    items.append(oneShot(userID: userID, reminder: reminder, title: title, fire: until))
                }
                continue
            }
            if reminder.status == .snoozed, let until = reminder.snoozedUntil, until > now {
                items.append(oneShot(userID: userID, reminder: reminder, title: title, fire: until))
                continue
            }
            let offsets = Array(Set(reminder.alertOffsets.isEmpty ? [0] : reminder.alertOffsets.filter { (-10080...0).contains($0) })).sorted()
            if let kind = simpleKind(reminder.rrule), let anchor = reminder.dueUTC ?? reminder.nextFires.first {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: reminder.timeZone) ?? .gmt
                let days: [Int?] = kind == "weekdays" ? (1...5).map { Optional($0) } : [nil]
                for day in days {
                    for offset in offsets where offset == 0 {
                        var base = anchor
                        if let day {
                            let weekday = calendar.component(.weekday, from: anchor)
                            let mondayBased = weekday == 1 ? 7 : weekday - 1
                            base = calendar.date(byAdding: .day, value: day - mondayBased, to: anchor) ?? anchor
                        }
                        let shifted = base.addingTimeInterval(Double(offset) * 60)
                        var parts = calendar.dateComponents([.hour, .minute], from: shifted)
                        let targetWeekday = kind == "daily" ? nil : calendar.component(.weekday, from: shifted)
                        if let targetWeekday { parts.weekday = targetWeekday }
                        guard let fire = calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTimePreservingSmallerComponents, repeatedTimePolicy: .first) else { continue }
                        let suffix = day.map { "wd.\($0)" } ?? kind
                        let extra = offset == 0 ? "" : ".pre.\(offset)"
                        let mondayDay = targetWeekday.map { $0 == 1 ? 7 : $0 - 1 }
                        items.append(PlannedNotification(identifier: "vb.\(userID).rem.\(reminder.id).\(suffix)\(extra)",
                            reminderID: reminder.id, userID: userID, title: title, fireDate: fire, repeats: true,
                            weekday: mondayDay, timeZone: reminder.timeZone))
                    }
                }
                // Advance alerts use server occurrence instants so DST transitions cannot shift their offset.
                for occurrence in reminder.nextFires.isEmpty ? [anchor] : reminder.nextFires {
                    for offset in offsets where offset != 0 {
                        let fire = occurrence.addingTimeInterval(Double(offset) * 60)
                        if fire > now && fire <= now.addingTimeInterval(horizon) {
                            items.append(oneShot(userID: userID, reminder: reminder, title: title, fire: fire))
                        }
                    }
                }
            } else {
                for occurrence in reminder.nextFires {
                    for offset in offsets {
                        let fire = occurrence.addingTimeInterval(Double(offset) * 60)
                        if fire > now && fire <= now.addingTimeInterval(horizon) {
                            items.append(oneShot(userID: userID, reminder: reminder, title: title, fire: fire))
                        }
                    }
                }
            }
        }
        var seen = Set<String>()
        return Array(items.sorted { $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate }
            .filter { seen.insert($0.identifier).inserted }.prefix(maxPending)).map {
                var item = $0; item.soundEnabled = settings.soundEnabled; return item
            }
    }

    public static func eligibleReminderIDs(_ reminders: [Reminder], settings: NotificationSettings,
                                           overrides: [ReminderLocalOverride] = []) -> Set<Int> {
        guard settings.enabled, settings.categories["reminder"] == true else { return [] }
        return Set(reminders.filter { reminder in
            guard reminder.notify, [.scheduled, .due, .snoozed].contains(reminder.status),
                  !overrides.contains(where: { $0.reminderID == reminder.id && $0.action == "complete" }) else { return false }
            let botID = reminder.assigneeBotId ?? reminder.sourceBotId
            return reminder.createdBy == "user" || botID.map { !settings.mutedBots.contains($0) } ?? true
        }.map(\.id))
    }

    public static func cancelDelivered(userID: Int, validReminderIDs: Set<Int>, identifiers: [String]) -> [String] {
        let prefix = "vb.\(userID).rem."
        return identifiers.filter { identifier in
            guard identifier.hasPrefix(prefix), let id = Int(identifier.dropFirst(prefix.count).split(separator: ".").first ?? "") else { return false }
            return !validReminderIDs.contains(id)
        }
    }

    public static func reconcile(userID: Int, desired: [PlannedNotification], existing: [ScheduledLocalNotification]) -> (remove: [String], add: [PlannedNotification]) {
        let prefix = "vb.\(userID).rem."
        let wanted = Dictionary(uniqueKeysWithValues: desired.map { ($0.identifier, $0) })
        var remove: [String] = []
        for item in existing where item.identifier.hasPrefix(prefix) {
            if let match = wanted[item.identifier] {
                if match.title != item.title || match.repeats != item.repeats || match.signature != item.signature {
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
        guard Set(parts.keys).isSubset(of: ["FREQ", "INTERVAL", "BYDAY"]) else { return nil }
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
                                   userID: userID, title: title, fireDate: fire, repeats: false, timeZone: reminder.timeZone)
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
    public static func fileName(userID: Int, server: String? = nil) -> String {
        guard let server else { return "outbox-\(userID).json" }
        let digest = SHA256.hash(data: Data(server.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "outbox-\(digest)-\(userID).json"
    }

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
        status == 404 || status == 409 && (code == "invalid_transition" || code == "version_conflict")
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
