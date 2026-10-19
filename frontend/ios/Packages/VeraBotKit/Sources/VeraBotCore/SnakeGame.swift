/// Local, deterministic Snake rules. Input and time are supplied by the caller.
public struct SnakeGame: Sendable {
    public struct Cell: Hashable, Sendable {
        public let column: Int
        public let row: Int
        public init(column: Int, row: Int) { self.column = column; self.row = row }
    }
    public enum Direction: Sendable {
        case up, right, down, left

        fileprivate var opposite: Self {
            switch self { case .up: .down; case .right: .left; case .down: .up; case .left: .right }
        }

        fileprivate var delta: Cell {
            switch self {
            case .up: Cell(column: 0, row: -1)
            case .right: Cell(column: 1, row: 0)
            case .down: Cell(column: 0, row: 1)
            case .left: Cell(column: -1, row: 0)
            }
        }
    }
    public enum Phase: Sendable { case ready, running, paused, lost, won }
    public enum EndReason: Sendable { case wall, body }
    public let width: Int
    public let height: Int
    public private(set) var snake: [Cell]
    public private(set) var food: Cell?
    public private(set) var direction: Direction = .right
    public private(set) var phase: Phase = .ready
    public private(set) var endReason: EndReason?
    public private(set) var score = 0
    private var queuedDirections: [Direction] = []
    /// 规则层产生的结果音效事件（吃食 / 结束 / 胜利），供视图层一次性取走，避免在重绘时猜测。
    public private(set) var soundEvents: [GameSoundEvent] = []
    /// 每次写入 soundEvents 时递增；视图用它触发取走事件。
    public private(set) var soundEventsVersion = 0
    public var tickIntervalMilliseconds: Int { max(90, 240 - (level - 1) * 20) }
    public var level: Int { 1 + score / 40 }

    public init() {
        var random = SystemRandomNumberGenerator()
        self.init(using: &random)
    }
    public init<R: RandomNumberGenerator>(width: Int = 20, height: Int = 20, using random: inout R) {
        precondition(width >= 2 && height >= 2)
        self.width = width
        self.height = height
        let column = min(width - 1, max(3, width / 2))
        snake = (0..<min(4, width)).map { Cell(column: column - $0, row: height / 2) }
        food = nil
        spawnFood(using: &random)
    }

    public mutating func start() {
        guard phase == .ready || phase == .paused else { return }
        queuedDirections.removeAll()
        phase = .running
    }

    public mutating func pause() {
        guard phase == .running else { return }
        queuedDirections.removeAll()
        phase = .paused
    }

    @discardableResult public mutating func turn(_ requested: Direction) -> Bool {
        guard phase == .running, queuedDirections.count < 2 else { return false }
        let previous = queuedDirections.last ?? direction
        guard requested != previous, requested != previous.opposite else { return false }
        queuedDirections.append(requested)
        return true
    }

    public mutating func tick() {
        var random = SystemRandomNumberGenerator()
        tick(using: &random)
    }

    public mutating func tick<R: RandomNumberGenerator>(using random: inout R) {
        guard phase == .running else { return }
        if !queuedDirections.isEmpty { direction = queuedDirections.removeFirst() }
        let next = Cell(column: snake[0].column + direction.delta.column,
                        row: snake[0].row + direction.delta.row)
        guard (0..<width).contains(next.column), (0..<height).contains(next.row) else {
            finish(reason: .wall)
            return
        }
        let growing = next == food
        // A non-growing step vacates the tail at the same time the head moves.
        guard !snake.dropLast(growing ? 0 : 1).contains(next) else {
            finish(reason: .body)
            return
        }
        snake.insert(next, at: 0)
        if growing {
            score += 10
            emit(.eat)
            spawnFood(using: &random)
        } else {
            snake.removeLast()
        }
    }

    /// 取走并清空规则层累积的音效事件。
    public mutating func drainSoundEvents() -> [GameSoundEvent] {
        let events = soundEvents
        soundEvents.removeAll()
        return events
    }

    private mutating func emit(_ event: GameSoundEvent) {
        soundEvents.append(event)
        soundEventsVersion &+= 1
    }

    private mutating func finish(reason: EndReason) {
        phase = .lost
        endReason = reason
        queuedDirections.removeAll()
        emit(.gameOver)
    }

    private mutating func spawnFood<R: RandomNumberGenerator>(using random: inout R) {
        let occupied = Set(snake)
        var free: [Cell] = []
        for row in 0..<height {
            for column in 0..<width {
                let cell = Cell(column: column, row: row)
                if !occupied.contains(cell) { free.append(cell) }
            }
        }
        food = free.randomElement(using: &random)
        if food == nil {
            if phase == .running { emit(.win) }
            phase = .won
            queuedDirections.removeAll()
        }
    }
}
