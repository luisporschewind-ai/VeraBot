import Foundation

struct BotAvatarLabPlayback {
    enum Mode: Equatable { case none, all, currentLoop, transitions }
    private(set) var mode: Mode = .none
    private(set) var serial: UInt64 = 0
    private(set) var sequence: [BotAvatarState] = []
    var running: Bool { mode != .none }
    mutating func start(_ mode: Mode, current: BotAvatarState) {
        serial &+= 1
        self.mode = mode
        switch mode {
        case .none: sequence = []
        case .all: sequence = BotAvatarState.allCases
        case .currentLoop: sequence = [current]
        case .transitions: sequence = [.thinking,.working,.delegating,.replying,.awaitingConfirmation,.success,.idle]
        }
    }
    mutating func stop() { start(.none, current: .idle) }
    func holdMS(_ state: BotAvatarState) -> Double { state.descriptor.demoMS }
}
