import Foundation

public struct GroupChatState: Sendable {
    public let groupID: Int
    public var activeTurnID: Int?
    public var status: GroupTurnStatus?
    public var messages: [GroupMessage] = []
    public var speakerMemberIDs: [Int] = []
    public var activeMemberID: Int?
    public var phase: String?
    public var errorMessage: String?
    public init(groupID: Int) { self.groupID = groupID }
}

public enum GroupChatReducer {
    public static func apply(_ event: GroupChatEvent, to state: inout GroupChatState) {
        guard event.groupID == state.groupID else { return }
        if case .turnStart(let message, let speakers) = event.payload {
            guard message.groupID == state.groupID, message.turnID <= event.turnID, message.turnID > 0, message.role == .user else { return }
            if let current = state.activeTurnID {
                if event.turnID < current || (event.turnID == current && state.status != .running) { return }
                if event.turnID > current && state.status == .running { return }
            }
            if state.activeTurnID != event.turnID {
                state.activeTurnID = event.turnID; state.status = .running
                state.errorMessage = nil; state.activeMemberID = nil; state.phase = nil
                state.speakerMemberIDs = speakers
            }
            if !state.messages.contains(where: { $0.id == message.id }) { state.messages.append(message) }
            return
        }
        guard state.activeTurnID == event.turnID, state.status == .running else { return }
        func index(_ mid: Int, _ member: Int) -> Int? {
            state.messages.firstIndex { $0.id == mid && $0.memberID == member && $0.turnID == event.turnID && $0.groupID == state.groupID && $0.role == .bot }
        }
        switch event.payload {
        case .messageStart(let message):
            guard message.groupID == state.groupID, message.turnID == event.turnID, message.role == .bot,
                  message.status == .streaming, let member = message.memberID, state.speakerMemberIDs.contains(member),
                  !state.messages.contains(where: { $0.id == message.id }) else { return }
            state.messages.append(message); state.activeMemberID = member; state.phase = nil
        case .delta(let mid, let member, let text):
            guard let i = index(mid, member), state.messages[i].status == .streaming else { return }
            state.messages[i].content += text
        case .status(let mid, let member, let phase):
            guard let i = index(mid, member), state.messages[i].status == .streaming else { return }
            state.activeMemberID = member; state.phase = phase
        case .messageDone(let message):
            guard message.groupID == state.groupID, message.turnID == event.turnID, message.role == .bot,
                  message.status != .streaming, let member = message.memberID, state.speakerMemberIDs.contains(member) else { return }
            if let i = index(message.id, member) {
                guard state.messages[i].status == .streaming else { return }
                state.messages[i] = message
            } else if !state.messages.contains(where: { $0.id == message.id }) { state.messages.append(message) }
            state.activeMemberID = nil; state.phase = nil
        case .error(_, let message, let mid):
            guard mid == nil || state.messages.contains(where: { $0.id == mid && $0.turnID == event.turnID }) else { return }
            state.errorMessage = message
        case .turnDone(let status, _, _):
            guard status != .running else { return }
            state.status = status; state.activeMemberID = nil; state.phase = nil
        case .turnStart: break
        }
    }

    /// Replaces this turn's partial bubbles with persisted messages; never appends old deltas.
    public static func restore(_ turn: GroupTurn, to state: inout GroupChatState) {
        guard turn.groupID == state.groupID, turn.id >= (state.activeTurnID ?? 0),
              turn.messages.allSatisfy({ $0.groupID == turn.groupID && $0.turnID == turn.id }),
              Set(turn.messages.map(\.id)).count == turn.messages.count else { return }
        state.messages.removeAll { $0.turnID == turn.id }
        state.messages.append(contentsOf: turn.messages); state.messages.sort { $0.id < $1.id }
        state.activeTurnID = turn.id; state.status = turn.status
        state.speakerMemberIDs = Array(Set(turn.messages.compactMap(\.memberID)))
        state.activeMemberID = turn.messages.last { $0.status == .streaming }?.memberID
        state.phase = nil; state.errorMessage = nil
    }
}
