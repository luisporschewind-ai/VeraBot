import Foundation

/// Value-only scheduling policy. The presentation owns its cancellable display timer.
struct NoticeQueue<Message: Equatable> {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let key: String
        let message: Message
    }

    private(set) var current: Entry?
    private(set) var pending: [Entry] = []
    let capacity: Int

    init(capacity: Int = 5) { self.capacity = max(1, capacity) }

    mutating func show(_ message: Message, key: String, replacing: Bool = false) {
        if let current, current.key == key, current.message == message { return }
        let entry = Entry(id: UUID(), key: key, message: message)
        if current == nil || current?.key == key || replacing {
            pending.removeAll { $0.key == key }
            current = entry
        } else if let index = pending.firstIndex(where: { $0.key == key }) {
            if pending[index].message != message { pending[index] = entry }
        } else {
            if pending.count >= capacity { pending.removeFirst() }
            pending.append(entry)
        }
    }

    mutating func dismiss(id: UUID) {
        guard current?.id == id else { return }
        current = pending.isEmpty ? nil : pending.removeFirst()
    }
    mutating func remove(key: String) {
        pending.removeAll { $0.key == key }
        if let current, current.key == key { dismiss(id: current.id) }
    }
    mutating func clear() { current = nil; pending.removeAll() }
}
