/// One visible private-chat entry. Shared persistence is rehydrated on every entry;
/// an incoming Feed citation belongs to this entry instance and is inserted once.
public struct PrivateChatDraftSession: Sendable {
    public private(set) var text = ""
    public private(set) var isActive = false
    public private(set) var isHydrating = false
    private var generation: UInt64 = 0
    private var revision: UInt64 = 0
    private var dirty = false
    private let incoming: String?
    private var incomingConsumed = false

    public init(incoming: String? = nil) { self.incoming = incoming }

    /// The retained view's prior buffer is not an editable snapshot of the latest shared draft.
    public mutating func begin() -> UInt64 {
        generation &+= 1; revision = 0
        isActive = true; isHydrating = true; dirty = false; text = ""
        return generation
    }

    public mutating func hydrate(saved: String, entry: UInt64) -> String? {
        guard isActive, isHydrating, generation == entry else { return nil }
        let typedWhileLoading = dirty
        text = typedWhileLoading ? FeedChatDraft.merging(existing: saved, incoming: text.isEmpty ? nil : text) : saved
        if !incomingConsumed {
            text = FeedChatDraft.merging(existing: text, incoming: incoming)
            incomingConsumed = true
            if let incoming, !incoming.isEmpty { dirty = true }
        }
        isHydrating = false
        return text
    }

    /// Returns false for hydration assignments and updates delivered to an inactive retained view.
    @discardableResult public mutating func edit(_ value: String) -> Bool {
        guard isActive, text != value else { return false }
        text = value; revision &+= 1; dirty = true
        return true
    }

    public var pendingWrite: PrivateChatDraftWrite? {
        guard isActive, !isHydrating, dirty else { return nil }
        return PrivateChatDraftWrite(entry: generation, revision: revision, text: text)
    }

    public func canSave(_ write: PrivateChatDraftWrite) -> Bool {
        isActive && !isHydrating && dirty && write.entry == generation && write.revision == revision && write.text == text
    }

    public mutating func acknowledge(_ write: PrivateChatDraftWrite) {
        guard canSave(write) else { return }
        dirty = false
    }

    /// Flush only edits made by an active, hydrated entry. Never flush an unhydrated stale buffer.
    public mutating func leave() -> String? {
        let flush = pendingWrite?.text
        isActive = false; isHydrating = false; dirty = false; generation &+= 1
        return flush
    }
}

public struct PrivateChatDraftWrite: Sendable, Equatable {
    public let entry: UInt64
    public let revision: UInt64
    public let text: String
}
