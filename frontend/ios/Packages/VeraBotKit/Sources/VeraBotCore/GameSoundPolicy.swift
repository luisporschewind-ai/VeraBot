/// No audio framework or wall clock: callers supply monotonic event IDs and time.
public enum GameSoundCommand: Equatable, Sendable {
    case play(UInt64, GameSoundEvent)
    case stopVoice(UInt64)
    case stopAll
}

public struct GameSoundPolicy: Sendable {
    private struct Voice: Sendable { let id: UInt64; let event: GameSoundEvent }
    private var voices: [Voice] = []
    private var enabled = true
    private var active = false
    private var routeBlocked = false
    private var lastEventID: Int64 = -1
    private var lastKeyTime: Int?
    private var nextVoice: UInt64 = 0
    public var canPlay: Bool { enabled && active && !routeBlocked }
    public var voiceCount: Int { voices.count }
    public init() {}

    @discardableResult public mutating func setEnabled(_ value: Bool) -> [GameSoundCommand] {
        enabled = value
        if value { routeBlocked = false }
        return value ? [] : stop()
    }
    @discardableResult public mutating func setActive(_ value: Bool) -> [GameSoundCommand] {
        active = value
        return value ? [] : stop()
    }
    @discardableResult public mutating func routeDisconnected() -> [GameSoundCommand] {
        routeBlocked = true
        return stop()
    }
    @discardableResult public mutating func reset() -> [GameSoundCommand] {
        lastEventID = -1
        lastKeyTime = nil
        return stop()
    }
    public mutating func finished(_ voice: UInt64) { voices.removeAll { $0.id == voice } }
    public mutating func request(_ event: GameSoundEvent, id: Int64, nowMs: Int) -> [GameSoundCommand] {
        guard id > lastEventID else { return [] }
        lastEventID = id // dropped events are never replayed after foreground/preemption.
        guard enabled, active, !routeBlocked else { return [] }
        if event == .keyPress {
            if let lastKeyTime, nowMs - lastKeyTime < 80 { return [] }
            lastKeyTime = nowMs
        }
        var commands: [GameSoundCommand] = []
        if event == .clearSingle || event == .clearMulti {
            for voice in voices where voice.event == .hardDrop { commands.append(.stopVoice(voice.id)) }
            voices.removeAll { $0.event == .hardDrop }
        }
        if voices.count == 4 {
            // Array order is arrival order, so equal priority evicts the oldest voice.
            let minimum = voices.map { priority($0.event) }.min()!
            guard priority(event) >= minimum else { return commands }
            let index = voices.firstIndex { priority($0.event) == minimum }!
            commands.append(.stopVoice(voices.remove(at: index).id))
        }
        nextVoice &+= 1
        voices.append(Voice(id: nextVoice, event: event))
        commands.append(.play(nextVoice, event))
        return commands
    }
    private mutating func stop() -> [GameSoundCommand] { voices.removeAll(); return [.stopAll] }
    private func priority(_ event: GameSoundEvent) -> Int {
        switch event {
        case .gameOver, .win: 3
        case .clearSingle, .clearMulti, .eat: 2
        case .hardDrop, .start, .pause, .resume: 1
        case .keyPress: 0
        }
    }
}
