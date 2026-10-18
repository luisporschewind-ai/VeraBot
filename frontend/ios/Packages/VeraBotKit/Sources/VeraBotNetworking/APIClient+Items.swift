import Foundation
import VeraBotCore

public struct ItemWrite: Encodable, Sendable {
    public var title: String?
    public var note: String?
    public var clearNote: Bool
    public var dueAt: String?
    public var clearDue: Bool
    public var timeZone: String?
    public var allDay: Bool?
    public var rrule: String?
    public var clearRrule: Bool
    public var priority: Int?
    public var assigneeBotId: Int?
    public var clearAssignee: Bool
    public var notify: Bool?
    public var expectedVersion: Int?
    public var checklist: [ChecklistWrite]?
    public var sourceKind: String?

    enum CodingKeys: String, CodingKey {
        case title, note, priority, notify, rrule, checklist
        case dueAt = "due_at"
        case timeZone = "timezone"
        case allDay = "all_day"
        case assigneeBotId = "assignee_bot_id"
        case expectedVersion = "expected_version"
        case sourceKind = "source_kind"
    }

    public init(title: String? = nil, note: String? = nil, dueAt: String? = nil, clearDue: Bool = false,
                timeZone: String? = nil, allDay: Bool? = nil, rrule: String? = nil, clearRrule: Bool = false,
                priority: Int? = nil, assigneeBotId: Int? = nil, clearAssignee: Bool = false, notify: Bool? = nil,
                expectedVersion: Int? = nil, clearNote: Bool = false, checklist: [ChecklistWrite]? = nil,
                sourceKind: String? = nil) {
        self.title = title
        self.note = note
        self.clearNote = clearNote
        self.dueAt = dueAt
        self.clearDue = clearDue
        self.timeZone = timeZone
        self.allDay = allDay
        self.rrule = rrule
        self.clearRrule = clearRrule
        self.priority = priority
        self.assigneeBotId = assigneeBotId
        self.clearAssignee = clearAssignee
        self.notify = notify
        self.expectedVersion = expectedVersion
        self.checklist = checklist
        self.sourceKind = sourceKind
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        if clearNote { try c.encodeNil(forKey: .note) } else { try c.encodeIfPresent(note, forKey: .note) }
        if clearDue { try c.encodeNil(forKey: .dueAt) } else { try c.encodeIfPresent(dueAt, forKey: .dueAt) }
        try c.encodeIfPresent(timeZone, forKey: .timeZone)
        try c.encodeIfPresent(allDay, forKey: .allDay)
        if clearRrule { try c.encodeNil(forKey: .rrule) } else { try c.encodeIfPresent(rrule, forKey: .rrule) }
        try c.encodeIfPresent(priority, forKey: .priority)
        if clearAssignee { try c.encodeNil(forKey: .assigneeBotId) } else { try c.encodeIfPresent(assigneeBotId, forKey: .assigneeBotId) }
        try c.encodeIfPresent(notify, forKey: .notify)
        try c.encodeIfPresent(expectedVersion, forKey: .expectedVersion)
        try c.encodeIfPresent(checklist, forKey: .checklist)
        try c.encodeIfPresent(sourceKind, forKey: .sourceKind)
    }
}

public struct ChecklistWrite: Encodable, Sendable {
    public var text: String
    public var done: Bool
    public init(text: String, done: Bool = false) {
        self.text = text
        self.done = done
    }
}

private struct ChecklistReplaceBody: Encodable {
    var expected_version: Int
    var items: [ChecklistWrite]
}

private struct ChecklistToggleBody: Encodable {
    var done: Bool?
}

private struct ItemSnoozeBody: Encodable {
    var minutes: Int?
    var until: String?
}

extension APIClient {
    public func items(view: String? = nil, botID: Int? = nil, cursor: String? = nil,
                      limit: Int = 200) async throws -> ItemsResponse {
        var params: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let view { params.append(.init(name: "view", value: view)) }
        if let botID { params.append(.init(name: "bot_id", value: String(botID))) }
        if let cursor, !cursor.isEmpty { params.append(.init(name: "cursor", value: cursor)) }
        return try await call("/api/items", query: params)
    }

    public func item(id: Int) async throws -> Item {
        try await call("/api/items/\(id)")
    }

    public func createItem(_ body: ItemWrite, idempotencyKey: String? = nil) async throws -> Item {
        try await call("/api/items", method: "POST", body: try encode(body), headers: idempotency(idempotencyKey))
    }

    public func updateItem(id: Int, _ body: ItemWrite, idempotencyKey: String? = nil) async throws -> Item {
        try await call("/api/items/\(id)", method: "PATCH", body: try encode(body), headers: idempotency(idempotencyKey))
    }

    public func completeItem(_ id: Int, idempotencyKey: String? = nil) async throws -> Item {
        try await call("/api/items/\(id)/complete", method: "POST", body: Data("{}".utf8),
                       headers: idempotency(idempotencyKey))
    }

    public func reopenItem(_ id: Int, idempotencyKey: String? = nil) async throws -> Item {
        try await call("/api/items/\(id)/reopen", method: "POST", body: Data("{}".utf8),
                       headers: idempotency(idempotencyKey))
    }

    public func snoozeItem(_ id: Int, minutes: Int? = nil, until: String? = nil,
                           idempotencyKey: String? = nil) async throws -> Item {
        try await call("/api/items/\(id)/snooze", method: "POST",
                       body: try encode(ItemSnoozeBody(minutes: minutes, until: until)),
                       headers: idempotency(idempotencyKey))
    }

    public func skipItem(_ id: Int, idempotencyKey: String? = nil) async throws -> Item {
        try await call("/api/items/\(id)/skip", method: "POST", body: Data("{}".utf8),
                       headers: idempotency(idempotencyKey))
    }

    public func replaceChecklist(id: Int, expectedVersion: Int, items: [ChecklistWrite],
                                 idempotencyKey: String? = nil) async throws -> Item {
        try await call("/api/items/\(id)/checklist", method: "PUT",
                       body: try encode(ChecklistReplaceBody(expected_version: expectedVersion, items: items)),
                       headers: idempotency(idempotencyKey))
    }

    public func toggleChecklist(id: Int, checklistID: Int, done: Bool? = nil) async throws -> Item {
        try await call("/api/items/\(id)/checklist/\(checklistID)", method: "PATCH",
                       body: try encode(ChecklistToggleBody(done: done)))
    }
}
