import Foundation

public struct NotificationEvent: Codable, Sendable {
    public var eventID: Int
    public var notificationID: Int
    public var operation: String
    public var notification: InboxNotification?
    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", notificationID = "notification_id", operation, notification
    }
    public init(eventID: Int, notificationID: Int, operation: String, notification: InboxNotification?) {
        self.eventID = eventID; self.notificationID = notificationID
        self.operation = operation; self.notification = notification
    }
}
public struct NotificationEventPage: Codable, Sendable {
    public var events: [NotificationEvent]
    public var nextCursor: Int
    public var upperBound: Int
    public var hasMore: Bool
    public var resetRequired: Bool
    public var serverTime: String?
    enum CodingKeys: String, CodingKey {
        case events, nextCursor = "next_cursor", upperBound = "upper_bound", hasMore = "has_more"
        case resetRequired = "reset_required", serverTime = "server_time"
    }
    public init(events: [NotificationEvent], nextCursor: Int, upperBound: Int, hasMore: Bool,
                resetRequired: Bool = false, serverTime: String? = nil) {
        self.events = events; self.nextCursor = nextCursor; self.upperBound = upperBound
        self.hasMore = hasMore; self.resetRequired = resetRequired; self.serverTime = serverTime
    }
}
public enum NotificationPresentation: Sendable { case silent, banner, system }
public enum NotificationEventPolicy {
    public static func decision(_ note: InboxNotification, settings: NotificationSettings,
                                visibleMessageIDs: Set<Int>, now: Date, isForeground: Bool) -> NotificationPresentation {
        guard note.isUnread, note.openedAt == nil, note.suppressionReason == nil,
              note.category != .reminder, note.category != .unknown,
              settings.enabled, settings.categories[note.category.rawValue] == true,
              let created = VeraBotDate.parse(note.createdAt), now.timeIntervalSince(created) < 300,
              now.timeIntervalSince(created) >= -60 else { return .silent }
        if let expires = VeraBotDate.parse(note.expiresAt), expires <= now { return .silent }
        if let bot = note.botId, settings.mutedBots.contains(bot) { return .silent }
        if note.category != .system, inQuietHours(settings, now: now) { return .silent }
        if isForeground, let message = note.messageId, visibleMessageIDs.contains(message) { return .silent }
        return isForeground ? .banner : .system
    }
    public static func inQuietHours(_ settings: NotificationSettings, now: Date) -> Bool {
        guard settings.quietEnabled else { return false }
        func minutes(_ text: String) -> Int? {
            let bits = text.split(separator: ":").compactMap { Int($0) }
            guard bits.count == 2, (0...23).contains(bits[0]), (0...59).contains(bits[1]) else { return nil }
            return bits[0] * 60 + bits[1]
        }
        guard let start = minutes(settings.quietStart), let end = minutes(settings.quietEnd), start != end else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.quietTimeZone) ?? .gmt
        let current = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return start < end ? current >= start && current < end : current >= start || current < end
    }
}
/// Encode the whole ledger atomically: pending events travel with the cursor.
public struct NotificationEventLedger: Codable, Sendable {
    public var cursor: Int?
    public var lastSync: Date?
    public private(set) var pending: [NotificationEvent] = []
    public private(set) var handled: [String: Date] = [:]
    public private(set) var attempts: [String: Int] = [:]
    public private(set) var retryAfter: [String: Date] = [:]
    public private(set) var presentedThreads: [String: Date] = [:]
    public init() {}
    public func needsBootstrap(now: Date) -> Bool {
        cursor == nil || lastSync == nil || now.timeIntervalSince(lastSync!) > 300
    }
    public mutating func bootstrap(cursor: Int, now: Date) {
        self.cursor = cursor; lastSync = now; pending.removeAll(); attempts.removeAll(); retryAfter.removeAll()
    }
    public mutating func ingest(_ page: NotificationEventPage, now: Date) {
        for event in page.events {
            if event.operation == "deleted" || event.notification?.isUnread == false {
                pending.removeAll { $0.notificationID == event.notificationID }
            } else if event.operation == "created", let note = event.notification, handled[note.localLogicalKey] == nil,
                      !pending.contains(where: { $0.notificationID == event.notificationID }) {
                pending.append(event)
            }
        }
        cursor = page.nextCursor; lastSync = now
        handled = handled.filter { now.timeIntervalSince($0.value) < 30 * 86400 }
        presentedThreads = presentedThreads.filter { now.timeIntervalSince($0.value) < 300 }
        if handled.count > 2000 { handled = Dictionary(uniqueKeysWithValues: handled.sorted { $0.value > $1.value }.prefix(2000).map { ($0.key, $0.value) }) }
    }
    public func coalesces(_ note: InboxNotification, now: Date) -> Bool {
        guard let date = presentedThreads[note.localThreadKey] else { return false }
        return now.timeIntervalSince(date) < 30
    }
    public func mayAttempt(_ note: InboxNotification, now: Date) -> Bool {
        retryAfter[note.localLogicalKey].map { now >= $0 } ?? true
    }
    public mutating func failed(_ note: InboxNotification, now: Date) {
        let key = note.localLogicalKey
        let count = (attempts[key] ?? 0) + 1
        attempts[key] = count
        if count >= 3 { finish(note, presented: false, now: now) }
        else { retryAfter[key] = now.addingTimeInterval(count == 1 ? 5 : 15) }
    }
    public mutating func finish(_ note: InboxNotification, presented: Bool, now: Date) {
        pending.removeAll { $0.notificationID == note.id }
        attempts.removeValue(forKey: note.localLogicalKey); retryAfter.removeValue(forKey: note.localLogicalKey)
        handled[note.localLogicalKey] = now
        if presented { presentedThreads[note.localThreadKey] = now }
    }
}
public extension InboxNotification {
    var localLogicalKey: String { logicalKey ?? "notification:\(id)" }
    var localThreadKey: String { threadId ?? localLogicalKey }
}

public enum NotificationTaskNoticeState { case success, failure, warning, awaitingConfirmation }
public extension InboxNotification {
    var taskNoticeState: NotificationTaskNoticeState {
        switch sourceState {
        case "failed": .failure
        case "interrupted": .warning
        case "awaiting_user", "awaiting_approval": .awaitingConfirmation
        default: .success
        }
    }
}
