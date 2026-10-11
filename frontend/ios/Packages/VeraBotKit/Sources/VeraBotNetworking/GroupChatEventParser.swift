import Foundation
import VeraBotCore

public enum GroupChatEventParser {
    private struct Envelope: Decodable {
        let group_id: Int; let turn_id: Int
        let user_message: GroupMessage?; let speaker_member_ids: [Int]?
        let message: JSONValue?; let message_id: Int?; let member_id: Int?
        let phase: String?; let text: String?; let code: String?
        let status: GroupTurnStatus?; let usage: JSONValue?; let message_ids: [Int]?
    }
    public static func parse(event: String, data: Data) -> GroupChatEvent? {
        guard let e = try? JSONDecoder().decode(Envelope.self, from: data), e.group_id > 0, e.turn_id > 0 else { return nil }
        func belongs(_ m: GroupMessage) -> Bool { m.id > 0 && m.groupID == e.group_id && m.turnID == e.turn_id }
        let payload: GroupChatEvent.Payload
        switch event {
        case "turn_start":
            guard let m = e.user_message, m.id > 0, m.groupID == e.group_id, m.turnID > 0, m.turnID <= e.turn_id, m.role == .user, m.memberID == nil,
                  m.status == .completed, let ids = e.speaker_member_ids, !ids.isEmpty,
                  ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else { return nil }
            payload = .turnStart(userMessage: m, speakerMemberIDs: ids)
        case "message_start", "message_done":
            // Error has a string `message`, while these events have an object.
            guard let raw = e.message, let encoded = try? JSONEncoder().encode(raw),
                  let m = try? JSONDecoder().decode(GroupMessage.self, from: encoded), belongs(m), m.role == .bot, let member = m.memberID, member > 0,
                  (event == "message_start" ? m.status == .streaming : m.status != .streaming) else { return nil }
            payload = event == "message_start" ? .messageStart(m) : .messageDone(m)
        case "status", "delta":
            guard let mid = e.message_id, mid > 0, let member = e.member_id, member > 0 else { return nil }
            if event == "status" {
                guard let phase = e.phase, !phase.isEmpty else { return nil }
                payload = .status(messageID: mid, memberID: member, phase: phase)
            } else {
                guard let text = e.text else { return nil }
                payload = .delta(messageID: mid, memberID: member, text: text)
            }
        case "error":
            guard let code = e.code, let body = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
                  e.message_id == nil || e.message_id! > 0 else { return nil }
            payload = .error(code: code, message: body.message, messageID: e.message_id)
        case "turn_done":
            guard let status = e.status, status != .running, let ids = e.message_ids,
                  ids.allSatisfy({ $0 > 0 }) else { return nil }
            payload = .turnDone(status: status, usage: e.usage, messageIDs: ids)
        default: return nil
        }
        return GroupChatEvent(groupID: e.group_id, turnID: e.turn_id, payload: payload)
    }
    private struct ErrorEnvelope: Decodable { let message: String }
}

/// SSE framing is independent of JSON events. Dispatch only at a blank line.
struct GroupSSEDecoder {
    var event = ""
    var data: [String] = []
    mutating func consume(_ line: String) -> GroupChatEvent? {
        if line.isEmpty {
            defer { event = ""; data = [] }
            return GroupChatEventParser.parse(event: event, data: Data(data.joined(separator: "\n").utf8))
        }
        if line.hasPrefix("event:") { event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5)); if value.hasPrefix(" ") { value.removeFirst() }; data.append(value)
        }
        return nil
    }
}
