import AVFoundation
import Foundation

public enum AudioOwner: Int, Sendable, CustomStringConvertible {
    case game = 1, tts, recording
    public var description: String { switch self { case .game: "game"; case .tts: "tts"; case .recording: "recording" } }
}

public struct AudioLease: Equatable, Sendable {
    public let id: UUID
    public let generation: UInt64
    public let owner: AudioOwner
}

public protocol AudioSessionDriver: Sendable {
    func activate(owner: AudioOwner) throws
    func deactivate() throws
}

private struct SystemAudioSessionDriver: AudioSessionDriver {
    func activate(owner: AudioOwner) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        switch owner {
        case .game: try session.setCategory(.ambient, mode: .default)
        case .tts: try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        case .recording: try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        }
        try session.setActive(true)
        #endif
    }
    func deactivate() throws {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

/// Acquisition and revocation happen synchronously on MainActor. Recording teardown may
/// release from an audio callback; the recursive lock serializes it with activation.
public final class AudioSessionCoordinator: @unchecked Sendable {
    public static let shared = AudioSessionCoordinator(driver: SystemAudioSessionDriver())
    private let driver: any AudioSessionDriver
    private let lock = NSRecursiveLock()
    private var current: AudioLease?
    private var pendingCleanup: AudioLease?
    private var revoked: (@MainActor @Sendable () -> Void)?
    private var generation: UInt64 = 0
    private var transitioning = false

    public init(driver: any AudioSessionDriver) { self.driver = driver }

    @MainActor
    public func acquire(owner: AudioOwner, onRevoked: @escaping @MainActor @Sendable () -> Void) throws -> AudioLease? {
        try lock.withLock {
            guard !transitioning else { return nil }
            transitioning = true
            defer { transitioning = false }
            if let current, current.owner.rawValue >= owner.rawValue { return nil }
            let stop = revoked
            current = nil
            revoked = nil
            // Clear identity before invoking stop: its late release cannot deactivate a successor.
            stop?()
            if pendingCleanup != nil {
                try driver.deactivate()
                pendingCleanup = nil
            }
            generation &+= 1
            let lease = AudioLease(id: UUID(), generation: generation, owner: owner)
            do {
                try driver.activate(owner: owner)
                current = lease
                revoked = onRevoked
                return lease
            } catch {
                pendingCleanup = lease
                do { try driver.deactivate(); pendingCleanup = nil } catch { /* retry only without a current owner */ }
                throw error
            }
        }
    }

    public func owns(_ lease: AudioLease) -> Bool { lock.withLock { current == lease } }

    public func release(_ lease: AudioLease) throws {
        try lock.withLock {
            guard current == lease || (current == nil && pendingCleanup == lease) else { return }
            current = nil
            revoked = nil
            pendingCleanup = lease
            try driver.deactivate()
            pendingCleanup = nil
        }
    }
}
