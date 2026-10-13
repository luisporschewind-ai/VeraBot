import Foundation

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
