import Foundation

/// Reserve before requesting; failed requests also count to prevent event bursts.
public struct TetrisCompanionPolicy: Sendable {
    public var isQuiet = false
    public private(set) var count = 0
    private var lastTime: TimeInterval?
    public init() {}
    public mutating func reserve(at time: TimeInterval) -> Bool {
        guard !isQuiet, count < 3, lastTime.map({ time - $0 >= 30 }) ?? true else { return false }
        count += 1
        lastTime = time
        return true
    }
}
