import Foundation

/// One active repeating direction. No queued actions survive release or cancellation.
public struct TetrisInputState: Sendable {
    public private(set) var heldAction: TetrisAction?
    private var nextRepeat: Int?
    private var lastTime = 0

    public init() {}

    public mutating func press(_ action: TetrisAction, atMilliseconds now: Int) -> [TetrisAction] {
        guard [.moveLeft, .moveRight, .softDrop].contains(action), action != heldAction,
              now >= lastTime else { return [] }
        heldAction = action
        lastTime = now
        nextRepeat = now + 180
        return [action]
    }

    public mutating func advance(toMilliseconds now: Int) -> [TetrisAction] {
        guard now >= lastTime else { return [] }
        lastTime = now
        guard let action = heldAction, let due = nextRepeat, now >= due else { return [] }
        // A delayed frame emits one action, never a backlog of old key presses.
        nextRepeat = now + 70
        return [action]
    }

    public mutating func release(_ action: TetrisAction) {
        if heldAction == action { cancel() }
    }

    public mutating func cancel() {
        heldAction = nil
        nextRepeat = nil
    }
}

/// Generation fences keep a cancelled countdown from resuming a later round.
public struct TetrisCountdownState: Sendable {
    public private(set) var remaining: Int?
    public private(set) var generation = 0
    public init() {}

    @discardableResult public mutating func start() -> Int {
        generation += 1
        remaining = 3
        return generation
    }

    public mutating func cancel() {
        generation += 1
        remaining = nil
    }

    public mutating func tick(generation expected: Int) -> Bool {
        guard generation == expected, let number = remaining else { return false }
        if number == 1 { remaining = nil; return true }
        remaining = number - 1
        return false
    }
}
