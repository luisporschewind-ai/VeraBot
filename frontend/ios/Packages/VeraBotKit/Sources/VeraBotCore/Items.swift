import Foundation

/// Bot 任务业务状态（只展示这些中文词，不暴露引擎内部态）。
public enum ItemTaskStatusLabel: String, Sendable, Hashable {
    case pending = "待执行"
    case running = "正在处理"
    case needsUser = "等你处理"
    case done = "已完成"
    case failed = "未完成"
}

public struct ItemTaskHistoryEntry: Codable, Sendable, Hashable {
    public var at: Date?
    public var ok: Bool

    public init(at: Date? = nil, ok: Bool = true) {
        self.at = at
        self.ok = ok
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try c.decodeIfPresent(String.self, forKey: .at) {
            at = VeraBotDate.parse(raw)
        } else {
            at = nil
        }
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
    }

    enum CodingKeys: String, CodingKey { case at, ok }
}

public struct ItemTaskSummary: Codable, Sendable, Hashable {
    public var kind: String
    public var id: Int
    public var status: String
    public var statusKey: String?
    public var nextRun: Date?
    public var lastResultSummary: String?
    public var needsUser: Bool
    public var messageId: Int?
    public var botId: Int?
    public var title: String?
    public var history: [ItemTaskHistoryEntry]
    public var waitQuestion: String?
    public var waitActionId: Int?

    enum CodingKeys: String, CodingKey {
        case kind, id, status, title, history
        case statusKey = "status_key"
        case nextRun = "next_run"
        case lastResultSummary = "last_result_summary"
        case needsUser = "needs_user"
        case messageId = "message_id"
        case botId = "bot_id"
        case waitQuestion = "wait_question"
        case waitActionId = "wait_action_id"
    }

    public init(kind: String, id: Int, status: String, statusKey: String? = nil, nextRun: Date? = nil,
                lastResultSummary: String? = nil, needsUser: Bool = false, messageId: Int? = nil,
                botId: Int? = nil, title: String? = nil, history: [ItemTaskHistoryEntry] = [],
                waitQuestion: String? = nil, waitActionId: Int? = nil) {
        self.kind = kind
        self.id = id
        self.status = status
        self.statusKey = statusKey
        self.nextRun = nextRun
        self.lastResultSummary = lastResultSummary
        self.needsUser = needsUser
        self.messageId = messageId
        self.botId = botId
        self.title = title
        self.history = history
        self.waitQuestion = waitQuestion
        self.waitActionId = waitActionId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        id = try c.decode(Int.self, forKey: .id)
        status = try c.decode(String.self, forKey: .status)
        statusKey = try c.decodeIfPresent(String.self, forKey: .statusKey)
        if let raw = try c.decodeIfPresent(String.self, forKey: .nextRun) {
            nextRun = VeraBotDate.parse(raw)
        } else {
            nextRun = nil
        }
        lastResultSummary = try c.decodeIfPresent(String.self, forKey: .lastResultSummary)
        needsUser = try c.decodeIfPresent(Bool.self, forKey: .needsUser) ?? false
        messageId = try c.decodeIfPresent(Int.self, forKey: .messageId)
        botId = try c.decodeIfPresent(Int.self, forKey: .botId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        history = try c.decodeIfPresent([ItemTaskHistoryEntry].self, forKey: .history) ?? []
        waitQuestion = try c.decodeIfPresent(String.self, forKey: .waitQuestion)
        waitActionId = try c.decodeIfPresent(Int.self, forKey: .waitActionId)
    }
}

public struct ChecklistEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var text: String
    public var done: Bool
    public var position: Int
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, text, done, position
        case updatedAt = "updated_at"
    }

    public init(id: Int, text: String, done: Bool = false, position: Int = 0, updatedAt: String? = nil) {
        self.id = id
        self.text = text
        self.done = done
        self.position = position
        self.updatedAt = updatedAt
    }
}

/// 统一事项（`GET /api/items`）。在 Reminder 字段之上附带清单与只读任务摘要。
public struct Item: Codable, Sendable, Hashable, Identifiable {
    public var reminder: Reminder
    public var checklist: [ChecklistEntry]
    public var task: ItemTaskSummary?

    public var id: Int { reminder.id }
    public var title: String { reminder.title }
    public var checklistDone: Int { reminder.checklistDone }
    public var checklistTotal: Int { reminder.checklistTotal }
    public var hasTask: Bool { reminder.taskId != nil || task != nil }

    public var checklistProgressText: String? {
        guard checklistTotal > 0 else { return nil }
        return "\(checklistDone)/\(checklistTotal)"
    }

    enum CodingKeys: String, CodingKey {
        case checklist, task
    }

    public init(reminder: Reminder, checklist: [ChecklistEntry] = [], task: ItemTaskSummary? = nil) {
        self.reminder = reminder
        self.checklist = checklist
        self.task = task
    }

    public init(from decoder: Decoder) throws {
        reminder = try Reminder(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checklist = try c.decodeIfPresent([ChecklistEntry].self, forKey: .checklist) ?? []
        task = try c.decodeIfPresent(ItemTaskSummary.self, forKey: .task)
    }

    public func encode(to encoder: Encoder) throws {
        try reminder.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(checklist, forKey: .checklist)
        try c.encodeIfPresent(task, forKey: .task)
    }
}

public struct ItemsResponse: Codable, Sendable {
    public var items: [Item]
    public var serverTime: String?
    public var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case serverTime = "server_time"
        case nextCursor = "next_cursor"
    }
}

public enum ItemBucket: String, Sendable, Hashable, CaseIterable {
    case today, planned, todo, bot, missed, done

    public var title: String {
        switch self {
        case .today: "今天"
        case .planned: "计划"
        case .todo: "待办"
        case .bot: "Bot 任务"
        case .missed: "已错过"
        case .done: "已完成"
        }
    }
}

public enum ItemListFilter: Sendable, Hashable {
    case all
    case createdByUser
    case createdByBot
    case bot(Int)
    case botTasksOnly
}

public enum ItemGrouping {
    /// 今天（含逾期）→ 计划 → 待办 → Bot 任务 → 已错过 → 已完成。有关联任务的未完成项进 Bot 任务。
    public static func bucket(of item: Item, now: Date = Date(), calendar: Calendar = .current) -> ItemBucket? {
        let reminder = item.reminder
        switch reminder.status {
        case .cancelled, .unknown:
            return nil
        case .missed:
            guard within(reminder, days: 30, now: now) else { return nil }
            return .missed
        case .done:
            guard within(reminder, days: 30, now: now) else { return nil }
            return .done
        case .due, .scheduled, .snoozed:
            if item.hasTask { return .bot }
            if reminder.status == .due { return .today }
            guard let date = reminder.scheduleDate else { return .todo }
            if date < calendar.startOfDay(for: now) { return .today }
            if calendar.isDate(date, inSameDayAs: now) { return .today }
            return .planned
        }
    }

    public static func matches(_ item: Item, filter: ItemListFilter) -> Bool {
        let reminder = item.reminder
        switch filter {
        case .all: return true
        case .createdByUser: return reminder.createdBy == "user"
        case .createdByBot: return reminder.createdBy == "bot"
        case .bot(let id): return reminder.sourceBotId == id || reminder.assigneeBotId == id
        case .botTasksOnly: return item.hasTask
        }
    }

    public static func sections(_ items: [Item], filter: ItemListFilter, showDone: Bool,
                                now: Date = Date(), calendar: Calendar = .current) -> [(ItemBucket, [Item])] {
        var grouped: [ItemBucket: [Item]] = [:]
        for item in items where matches(item, filter: filter) {
            guard let bucket = bucket(of: item, now: now, calendar: calendar) else { continue }
            if (bucket == .done || bucket == .missed) && !showDone { continue }
            grouped[bucket, default: []].append(item)
        }
        return ItemBucket.allCases.compactMap { bucket in
            guard var rows = grouped[bucket], !rows.isEmpty else { return nil }
            rows.sort { lhs, rhs in
                switch (lhs.reminder.scheduleDate, rhs.reminder.scheduleDate) {
                case let (l?, r?) where l != r: return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                default: break
                }
                if lhs.reminder.priority != rhs.reminder.priority { return lhs.reminder.priority > rhs.reminder.priority }
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
