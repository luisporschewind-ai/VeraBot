import Foundation

/// 提醒状态。未知字符串解码为 `.unknown`，旧后端缺字段时按 `done` 回退。
public enum ReminderStatus: String, Sendable, Hashable {
    case scheduled, due, snoozed, done, missed, cancelled, unknown
}

public enum ReminderBucket: String, Sendable, Hashable, CaseIterable {
    case due, today, upcoming, undated, missed, done

    public var title: String {
        switch self {
        case .due: "逾期"
        case .today: "今天"
        case .upcoming: "即将"
        case .undated: "无日期"
        case .missed: "已错过"
        case .done: "已完成"
        }
    }
}

public enum ReminderListFilter: Sendable, Hashable {
    case all
    case createdByUser
    case createdByBot
    case bot(Int)
}

/// 与 `GET /api/reminders` 的 Reminder 对象一一对应。日期字段按 ISO 解析，不靠切字符串。
public struct Reminder: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var content: String
    public var note: String?
    public var dueAt: String?
    public var dueUTC: Date?
    public var timeZone: String
    public var allDay: Bool
    public var rrule: String?
    public var repeatLabel: String?
    public var nextFires: [Date]
    public var status: ReminderStatus
    public var snoozedUntil: Date?
    public var priority: Int
    public var createdBy: String
    public var sourceBotId: Int?
    public var botName: String?
    public var assigneeBotId: Int?
    public var assigneeBotName: String?
    public var sourceMessageId: Int?
    public var notify: Bool
    public var alertOffsets: [Int]
    public var version: Int
    public var done: Int
    public var completedAt: String?
    public var cancelledAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, content, note, status, priority, done
        case rrule = "rrule"
        case notify = "notify"
        case version = "version"
        case dueAt = "due_at"
        case dueUTC = "due_utc"
        case timeZone = "timezone"
        case allDay = "all_day"
        case repeatLabel = "repeat_label"
        case nextFires = "next_fires"
        case snoozedUntil = "snoozed_until"
        case createdBy = "created_by"
        case sourceBotId = "source_bot_id"
        case botId = "bot_id"
        case botName = "bot_name"
        case assigneeBotId = "assignee_bot_id"
        case assigneeBotName = "assignee_bot_name"
        case sourceMessageId = "source_message_id"
        case alertOffsets = "alert_offsets"
        case completedAt = "completed_at"
        case cancelledAt = "cancelled_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(id: Int, title: String, content: String? = nil, note: String? = nil, dueAt: String? = nil,
                dueUTC: Date? = nil, timeZone: String = "Asia/Shanghai", allDay: Bool = false, rrule: String? = nil,
                repeatLabel: String? = nil, nextFires: [Date] = [], status: ReminderStatus = .scheduled,
                snoozedUntil: Date? = nil, priority: Int = 0, createdBy: String = "user", sourceBotId: Int? = nil,
                botName: String? = nil, assigneeBotId: Int? = nil, assigneeBotName: String? = nil,
                sourceMessageId: Int? = nil, notify: Bool = true, alertOffsets: [Int] = [0], version: Int = 1,
                done: Int? = nil, completedAt: String? = nil, cancelledAt: String? = nil,
                createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.title = title
        self.content = content ?? title
        self.note = note
        self.dueAt = dueAt
        self.dueUTC = dueUTC
        self.timeZone = timeZone
        self.allDay = allDay
        self.rrule = rrule
        self.repeatLabel = repeatLabel
        self.nextFires = nextFires
        self.status = status
        self.snoozedUntil = snoozedUntil
        self.priority = priority
        self.createdBy = createdBy
        self.sourceBotId = sourceBotId
        self.botName = botName
        self.assigneeBotId = assigneeBotId
        self.assigneeBotName = assigneeBotName
        self.sourceMessageId = sourceMessageId
        self.notify = notify
        self.alertOffsets = alertOffsets
        self.version = version
        self.done = done ?? (status == .done ? 1 : 0)
        self.completedAt = completedAt
        self.cancelledAt = cancelledAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        let rawTitle = try c.decodeIfPresent(String.self, forKey: .title)
        let rawContent = try c.decodeIfPresent(String.self, forKey: .content)
        title = rawTitle ?? rawContent ?? ""
        content = rawContent ?? title
        note = try c.decodeIfPresent(String.self, forKey: .note)
        dueAt = try c.decodeIfPresent(String.self, forKey: .dueAt)
        dueUTC = VeraBotDate.parse(try c.decodeIfPresent(String.self, forKey: .dueUTC))
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone) ?? "Asia/Shanghai"
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        rrule = try c.decodeIfPresent(String.self, forKey: .rrule)
        repeatLabel = try c.decodeIfPresent(String.self, forKey: .repeatLabel)
        let fires = try c.decodeIfPresent([String].self, forKey: .nextFires) ?? []
        nextFires = fires.compactMap(VeraBotDate.parse)
        snoozedUntil = VeraBotDate.parse(try c.decodeIfPresent(String.self, forKey: .snoozedUntil))
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy) ?? "user"
        let source = try c.decodeIfPresent(Int.self, forKey: .sourceBotId)
        let bot = try c.decodeIfPresent(Int.self, forKey: .botId)
        sourceBotId = source ?? bot
        botName = try c.decodeIfPresent(String.self, forKey: .botName)
        assigneeBotId = try c.decodeIfPresent(Int.self, forKey: .assigneeBotId)
        assigneeBotName = try c.decodeIfPresent(String.self, forKey: .assigneeBotName)
        sourceMessageId = try c.decodeIfPresent(Int.self, forKey: .sourceMessageId)
        alertOffsets = try c.decodeIfPresent([Int].self, forKey: .alertOffsets) ?? [0]
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        cancelledAt = try c.decodeIfPresent(String.self, forKey: .cancelledAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        if let raw = try c.decodeIfPresent(String.self, forKey: .status) {
            status = ReminderStatus(rawValue: raw) ?? .unknown
        } else if (try c.decodeIfPresent(Int.self, forKey: .done) ?? 0) == 1 {
            status = .done
        } else {
            status = .scheduled
        }
        done = try c.decodeIfPresent(Int.self, forKey: .done) ?? (status == .done ? 1 : 0)
        if try c.decodeIfPresent(Bool.self, forKey: .notify) == nil {
            notify = dueAt != nil || dueUTC != nil
        } else {
            notify = try c.decode(Bool.self, forKey: .notify)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(dueAt, forKey: .dueAt)
        try c.encodeIfPresent(dueUTC.map(VeraBotDate.format), forKey: .dueUTC)
        try c.encode(timeZone, forKey: .timeZone)
        try c.encode(allDay, forKey: .allDay)
        try c.encodeIfPresent(rrule, forKey: .rrule)
        try c.encodeIfPresent(repeatLabel, forKey: .repeatLabel)
        try c.encode(nextFires.map(VeraBotDate.format), forKey: .nextFires)
        try c.encode(status == .unknown ? "unknown" : status.rawValue, forKey: .status)
        try c.encodeIfPresent(snoozedUntil.map(VeraBotDate.format), forKey: .snoozedUntil)
        try c.encode(priority, forKey: .priority)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encodeIfPresent(sourceBotId, forKey: .sourceBotId)
        try c.encodeIfPresent(sourceBotId, forKey: .botId)
        try c.encodeIfPresent(botName, forKey: .botName)
        try c.encodeIfPresent(assigneeBotId, forKey: .assigneeBotId)
        try c.encodeIfPresent(assigneeBotName, forKey: .assigneeBotName)
        try c.encodeIfPresent(sourceMessageId, forKey: .sourceMessageId)
        try c.encode(notify, forKey: .notify)
        try c.encode(alertOffsets, forKey: .alertOffsets)
        try c.encode(version, forKey: .version)
        try c.encode(done, forKey: .done)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(cancelledAt, forKey: .cancelledAt)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    /// 来源名。Bot 已删除时显示「已删除的 Bot」。
    public var sourceName: String {
        if let botName, !botName.isEmpty { return botName }
        if createdBy == "bot" || sourceBotId != nil { return "已删除的 Bot" }
        return "我"
    }

    /// 排序和分组用的时刻：稍后看 `snoozed_until`，否则看 `due_utc`。
    public var scheduleDate: Date? {
        if status == .snoozed { return snoozedUntil ?? dueUTC ?? VeraBotDate.parse(dueAt) }
        return dueUTC ?? VeraBotDate.parse(dueAt)
    }
}

public struct ReminderCounts: Codable, Sendable, Hashable {
    public var due: Int
    public var today: Int
    public var upcoming: Int
    public var undated: Int
    public var missed: Int
    public var done: Int

    enum CodingKeys: String, CodingKey {
        case due, today, upcoming, undated, missed, done
    }

    public init(due: Int = 0, today: Int = 0, upcoming: Int = 0, undated: Int = 0, missed: Int = 0, done: Int = 0) {
        self.due = due
        self.today = today
        self.upcoming = upcoming
        self.undated = undated
        self.missed = missed
        self.done = done
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        due = try c.decodeIfPresent(Int.self, forKey: .due) ?? 0
        today = try c.decodeIfPresent(Int.self, forKey: .today) ?? 0
        upcoming = try c.decodeIfPresent(Int.self, forKey: .upcoming) ?? 0
        undated = try c.decodeIfPresent(Int.self, forKey: .undated) ?? 0
        missed = try c.decodeIfPresent(Int.self, forKey: .missed) ?? 0
        done = try c.decodeIfPresent(Int.self, forKey: .done) ?? 0
    }
}

public struct RemindersResponse: Codable, Sendable {
    public var reminders: [Reminder]
    public var serverTime: String?
    public var counts: ReminderCounts?

    enum CodingKeys: String, CodingKey {
        case reminders
        case serverTime = "server_time"
        case counts
    }

    public init(reminders: [Reminder], serverTime: String? = nil, counts: ReminderCounts? = nil) {
        self.reminders = reminders
        self.serverTime = serverTime
        self.counts = counts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reminders = try c.decodeIfPresent([Reminder].self, forKey: .reminders) ?? []
        serverTime = try c.decodeIfPresent(String.self, forKey: .serverTime)
        counts = try c.decodeIfPresent(ReminderCounts.self, forKey: .counts)
    }
}

public enum ReminderRepeatPreset: String, CaseIterable, Sendable, Identifiable {
    case never, daily, weekdays, weekly, monthly, yearly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .never: "永不"
        case .daily: "每天"
        case .weekdays: "工作日"
        case .weekly: "每周"
        case .monthly: "每月"
        case .yearly: "每年"
        }
    }

    public func rrule(on date: Date?, calendar: Calendar = .current) -> String? {
        switch self {
        case .never: return nil
        case .daily: return "FREQ=DAILY"
        case .weekdays: return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        case .weekly:
            let day = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][(calendar.component(.weekday, from: date ?? Date()) - 1 + 7) % 7]
            return "FREQ=WEEKLY;BYDAY=\(day)"
        case .monthly:
            let day = calendar.component(.day, from: date ?? Date())
            return "FREQ=MONTHLY;BYMONTHDAY=\(day)"
        case .yearly: return "FREQ=YEARLY"
        }
    }

    public static func matching(_ rule: String?) -> ReminderRepeatPreset {
        guard let rule, !rule.isEmpty else { return .never }
        if rule == "FREQ=DAILY" { return .daily }
        if rule == "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" { return .weekdays }
        if rule.hasPrefix("FREQ=WEEKLY") { return .weekly }
        if rule.hasPrefix("FREQ=MONTHLY") { return .monthly }
        if rule.hasPrefix("FREQ=YEARLY") { return .yearly }
        return .never
    }
}

public enum ReminderGrouping {
    /// 逾期 → 今天 → 即将 → 无日期 → 已错过（30 天）→ 已完成（30 天）。已取消不进列表。
    public static func bucket(of reminder: Reminder, now: Date = Date(), calendar: Calendar = .current) -> ReminderBucket? {
        switch reminder.status {
        case .cancelled, .unknown:
            return nil
        case .due:
            return .due
        case .missed:
            guard within(reminder, days: 30, now: now) else { return nil }
            return .missed
        case .done:
            guard within(reminder, days: 30, now: now) else { return nil }
            return .done
        case .scheduled, .snoozed:
            guard let date = reminder.scheduleDate else { return .undated }
            if calendar.isDate(date, inSameDayAs: now) { return .today }
            if date < calendar.startOfDay(for: now) { return .due }
            return .upcoming
        }
    }

    public static func matches(_ reminder: Reminder, filter: ReminderListFilter) -> Bool {
        switch filter {
        case .all: return true
        case .createdByUser: return reminder.createdBy == "user"
        case .createdByBot: return reminder.createdBy == "bot"
        case .bot(let id): return reminder.sourceBotId == id || reminder.assigneeBotId == id
        }
    }

    public static func sections(_ reminders: [Reminder], filter: ReminderListFilter, showDone: Bool,
                                now: Date = Date(), calendar: Calendar = .current) -> [(ReminderBucket, [Reminder])] {
        var grouped: [ReminderBucket: [Reminder]] = [:]
        for item in reminders where matches(item, filter: filter) {
            guard let bucket = bucket(of: item, now: now, calendar: calendar) else { continue }
            if bucket == .done && !showDone { continue }
            grouped[bucket, default: []].append(item)
        }
        return ReminderBucket.allCases.compactMap { bucket in
            guard var rows = grouped[bucket], !rows.isEmpty else { return nil }
            rows.sort { lhs, rhs in
                switch (lhs.scheduleDate, rhs.scheduleDate) {
                case let (l?, r?) where l != r: return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                default: break
                }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.id < rhs.id
            }
            return (bucket, rows)
        }
    }

    private static func within(_ reminder: Reminder, days: Int, now: Date) -> Bool {
        let stamp = VeraBotDate.parse(reminder.completedAt) ?? VeraBotDate.parse(reminder.updatedAt) ?? reminder.scheduleDate
        guard let stamp else { return true }
        return stamp >= now.addingTimeInterval(TimeInterval(-days * 24 * 3600))
    }
}

public enum ReminderTimeText {
    /// 按设备时区格式化。不截取 `due_at` 字符串。
    public static func when(_ reminder: Reminder, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = reminder.scheduleDate else { return "未设时间" }
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "今天"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
                  calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "明天"
        } else {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "zh_CN")
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            formatter.dateFormat = sameYear ? "M月d日" : "yyyy年M月d日"
            day = formatter.string(from: date)
        }
        if reminder.allDay { return "\(day) 全天" }
        let clock = DateFormatter()
        clock.calendar = calendar
        clock.timeZone = calendar.timeZone
        clock.locale = Locale(identifier: "zh_CN")
        clock.dateFormat = "HH:mm"
        return "\(day) \(clock.string(from: date))"
    }

    public static func subtitle(_ reminder: Reminder, now: Date = Date(), calendar: Calendar = .current) -> String {
        var parts = [when(reminder, now: now, calendar: calendar)]
        if let label = reminder.repeatLabel, !label.isEmpty {
            let name = label.split(separator: " ").first.map(String.init) ?? label
            if name != parts[0] { parts.append(name) }
        }
        parts.append("来自 \(reminder.sourceName)")
        return parts.joined(separator: " · ")
    }
}

public enum SnoozeChoice: String, CaseIterable, Sendable, Identifiable {
    case tenMinutes, oneHour, tonight, tomorrowMorning
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .tenMinutes: "10 分钟"
        case .oneHour: "1 小时"
        case .tonight: "今晚 20:00"
        case .tomorrowMorning: "明天 09:00"
        }
    }

    public func minutes(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        switch self {
        case .tenMinutes: return 10
        case .oneHour: return 60
        case .tonight, .tomorrowMorning: return nil
        }
    }

    public func until(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .tenMinutes, .oneHour:
            return nil
        case .tonight:
            var parts = calendar.dateComponents([.year, .month, .day], from: now)
            parts.hour = 20
            parts.minute = 0
            let tonight = calendar.date(from: parts) ?? now
            if tonight > now { return tonight }
            return calendar.date(byAdding: .day, value: 1, to: tonight)
        case .tomorrowMorning:
            let start = calendar.startOfDay(for: now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
    }
}

enum VeraBotDate {
    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return fallback.date(from: text)
    }

    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
