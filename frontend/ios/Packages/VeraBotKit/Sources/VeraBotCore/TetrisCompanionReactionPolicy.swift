import Foundation

public struct TetrisCompanionEpoch: Equatable, Sendable {
    public let round: UUID
    public let partner: Int
    public let session: UInt64
    public init(round: UUID, partner: Int, session: UInt64) {
        self.round = round; self.partner = partner; self.session = session
    }
    public func accepts(round: UUID, partner: Int, session: UInt64) -> Bool {
        self.round == round && self.partner == partner && self.session == session
    }
}

public struct TetrisCompanionReactionPolicy: Sendable {
    public struct Reaction: Equatable, Sendable {
        public enum Kind: Sendable { case idle, smile, success, warning, failure }
        public let kind: Kind
        public let durationMs: Int
    }
    private var dangerous = false
    public init() {}
    public mutating func consume(event: TetrisEventKind, height: Int, cleared: Int = 0) -> Reaction? {
        if height <= 12 { dangerous = false }
        switch event {
        case .ended: return .init(kind: .failure, durationMs: 1500)
        case .paused: return .init(kind: .idle, durationMs: 0)
        case .linesCleared where cleared > 0:
            return .init(kind: cleared == 1 ? .smile : .success, durationMs: cleared == 1 ? 1200 : 2000)
        case .locked where height >= 15 && !dangerous:
            dangerous = true
            return .init(kind: .warning, durationMs: 1200)
        default: return nil
        }
    }
}
