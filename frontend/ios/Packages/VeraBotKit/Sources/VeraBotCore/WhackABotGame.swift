/// Offline whack-a-mole rules. Time is active play time, supplied by a monotonic clock.
/// Target identities prevent a delayed tap from hitting a new Bot in the same hole.
public struct WhackABotGame: Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case normal, hard
    }
    public enum Phase: Sendable { case ready, running, paused, finished }

    public struct Target: Identifiable, Equatable, Sendable {
        public let id: Int
        public let hole: Int
        public let color: BotAvatarColorOption
        public let appearedAtMilliseconds: Int
        public fileprivate(set) var expiresAtMilliseconds: Int
        public fileprivate(set) var pointsAwarded: Int?
        /// Both correct hits and wrong-color hits consume this appearance.
        public var isHit: Bool { pointsAwarded != nil }
    }

    public let mode: Mode
    /// Hard mode colors are chosen once for a round; normal holes remain neutral.
    public let holeColors: [BotAvatarColorOption]
    public private(set) var score = 0
    public private(set) var wrongColorHits = 0
    public private(set) var phase: Phase = .ready
    public private(set) var targets: [Target] = []
    public private(set) var elapsedMilliseconds = 0
    public private(set) var hits = 0
    public private(set) var taps = 0
    private var nextSpawnMilliseconds = 0
    private var nextID = 0

    public init(mode: Mode = .normal) {
        var random = SystemRandomNumberGenerator()
        self.init(mode: mode, using: &random)
    }

    public init<R: RandomNumberGenerator>(mode: Mode = .normal, using random: inout R) {
        self.mode = mode
        holeColors = mode == .hard ? Array(BotAvatarColorPalette.all.shuffled(using: &random).prefix(9)) : []
    }

    public var remainingSeconds: Int { (60_000 - elapsedMilliseconds + 999) / 1_000 }
    public var accuracyPercent: Int { taps == 0 ? 0 : hits * 100 / taps }
    public var level: Int { min(3, elapsedMilliseconds / 20_000 + 1) }

    public mutating func start() {
        guard phase == .ready || phase == .paused else { return }
        phase = .running
    }

    public mutating func pause() {
        guard phase == .running else { return }
        phase = .paused
    }

    /// Advances through spawn and expiry events in order, even when a frame was delayed.
    public mutating func advance<R: RandomNumberGenerator>(milliseconds: Int, using random: inout R) {
        guard phase == .running, milliseconds > 0 else { return }
        let end = elapsedMilliseconds + min(milliseconds, 60_000 - elapsedMilliseconds)
        while true {
            let expiry = targets.map(\.expiresAtMilliseconds).min() ?? 60_000
            let event = min(nextSpawnMilliseconds, expiry)
            guard event <= end, event < 60_000 else { break }
            elapsedMilliseconds = event
            targets.removeAll { $0.expiresAtMilliseconds <= event }
            if nextSpawnMilliseconds == event {
                if targets.count < level {
                    let freeHoles = (0..<9).filter { hole in !targets.contains { $0.hole == hole } }
                    if let hole = freeHoles.randomElement(using: &random) {
                        nextID += 1
                        let lifetime = [1_350, 1_100, 1_000][level - 1]
                        targets.append(Target(id: nextID, hole: hole, color: BotAvatarColorPalette.all.randomElement(using: &random)!, appearedAtMilliseconds: event,
                                              expiresAtMilliseconds: event + lifetime))
                    }
                }
                nextSpawnMilliseconds = event + [850, 650, 450][level - 1]
            }
        }
        elapsedMilliseconds = end
        if end == 60_000 {
            phase = .finished
            targets.removeAll()
        }
    }

    /// Empty, repeated, and stale taps count toward accuracy but never subtract points.
    @discardableResult
    public mutating func tap(hole: Int, targetID: Int?) -> Bool {
        guard phase == .running, (0..<9).contains(hole) else { return false }
        taps += 1
        guard let index = targets.firstIndex(where: { $0.hole == hole && $0.id == targetID && !$0.isHit })
        else { return false }
        let correct = mode == .normal || targets[index].color == holeColors[hole]
        let points = correct ? 10 : -10
        if correct { hits += 1 } else { wrongColorHits += 1 }
        score = max(0, score + points)
        targets[index].pointsAwarded = points
        targets[index].expiresAtMilliseconds = elapsedMilliseconds + 220
        return correct
    }
}
