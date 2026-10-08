import Foundation

/// Preview edits do not change the saved document until a verified save succeeds.
public struct BotAppearanceDraft: Sendable {
    public private(set) var saved: BotAppearance
    public private(set) var current: BotAppearance
    public var isDirty: Bool { current != saved }
    public init(saved: BotAppearance) { self.saved = saved; self.current = saved }
    public mutating func update(_ value: BotAppearance) throws {
        try value.validate()
        current = value
    }
    public mutating func cancel() { current = saved }
    public mutating func markSaved() { saved = current }
}
