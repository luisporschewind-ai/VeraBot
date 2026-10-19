import Foundation

/// Serialize input startup, cancellation and the entire checked callback teardown.
/// Audio tap delivery uses its own short buffer lock and never acquires this gate.
public final class SpeechInputLifecycle: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var generation: UInt64 = 0
    public init() {}
    public func begin<T>(_ operation: (UInt64) throws -> T) rethrows -> T {
        try lock.withLock { generation &+= 1; return try operation(generation) }
    }
    public func invalidate<T>(_ operation: () throws -> T) rethrows -> T {
        try lock.withLock { generation &+= 1; return try operation() }
    }
    public func perform<T>(_ operation: () throws -> T) rethrows -> T {
        try lock.withLock(operation)
    }
    public func withCurrent<T>(_ expected: UInt64, _ operation: () throws -> T) rethrows -> T? {
        try lock.withLock {
            guard expected == generation else { return nil }
            return try operation()
        }
    }
}
