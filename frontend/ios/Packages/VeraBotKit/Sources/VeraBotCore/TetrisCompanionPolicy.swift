import Foundation

/// Reserve before requesting; failed requests also count to prevent event bursts.
public struct TetrisCompanionPolicy: Sendable {
    public enum Event: Sendable { case start, highlight, end }
    public var isQuiet = false
    public private(set) var count = 0
    private var lastTime: TimeInterval?
    private var endReserved = false
    public init() {}
    public mutating func reserve(event: Event, at time: TimeInterval) -> Bool {
        guard !endReserved, event == .end || count < 2 else { return false }
        guard reserve(at: time) else { return false }
        if event == .end { endReserved = true }
        return true
    }
    public mutating func reserve(at time: TimeInterval) -> Bool {
        guard !isQuiet, count < 3, lastTime.map({ time - $0 >= 30 }) ?? true else { return false }
        count += 1
        lastTime = time
        return true
    }
}
