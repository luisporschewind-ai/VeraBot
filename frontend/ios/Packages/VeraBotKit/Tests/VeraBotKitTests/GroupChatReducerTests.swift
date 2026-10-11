import Foundation
import Testing
import VeraBotCore

private func message(_ id: Int, _ member: Int?, _ text: String = "", _ status: GroupMessageStatus = .streaming) -> GroupMessage {
    GroupMessage(id: id, memberID: member, content: text, status: status, groupID: 7, turnID: 9)
}
private func apply(_ payload: GroupChatEvent.Payload, _ state: inout GroupChatState, turn: Int = 9, group: Int = 7) {
    GroupChatReducer.apply(GroupChatEvent(groupID: group, turnID: turn, payload: payload), to: &state)
}
private func started() -> GroupChatState {
    var state = GroupChatState(groupID: 7)
    apply(.turnStart(userMessage: message(100, nil, "讨论", .completed), speakerMemberIDs: [21,22]), &state)
    return state
}
@Test func GroupChatKeepsSpeakersSeparateAndStartIdempotent() {
    var state = started()
    apply(.messageStart(message(101, 21)), &state)
    apply(.delta(messageID: 101, memberID: 21, text: "A"), &state)
    apply(.messageStart(message(101, 21)), &state)
    apply(.messageStart(message(102, 22)), &state)
    apply(.delta(messageID: 102, memberID: 22, text: "B"), &state)
    #expect(state.messages.count == 3)
    #expect(state.messages.first { $0.id == 101 }?.content == "A")
    #expect(state.messages.first { $0.id == 102 }?.content == "B")
}
@Test func GroupChatDoneReplacesTextAndBlocksLateDelta() {
    var state = started()
    apply(.messageStart(message(101,21)), &state)
    apply(.delta(messageID: 101, memberID: 21, text: "片段"), &state)
    apply(.messageDone(message(101,21,"完整答案",.completed)), &state)
    apply(.delta(messageID: 101, memberID: 21, text: "重复"), &state)
    #expect(state.messages.last?.content == "完整答案")
    #expect(state.messages.last?.status == .completed)
}
@Test func GroupChatStatusAndWrongIdentityDoNotEnterBody() {
    var state = started()
    apply(.messageStart(message(101,21)), &state)
    apply(.status(messageID: 101, memberID: 21, phase: "thinking"), &state)
    apply(.delta(messageID: 101, memberID: 22, text: "错成员"), &state)
    apply(.delta(messageID: 101, memberID: 21, text: "错群"), &state, group: 8)
    apply(.delta(messageID: 101, memberID: 21, text: "旧轮"), &state, turn: 8)
    #expect(state.messages.last?.content == "")
    #expect(state.phase == "thinking" && state.activeMemberID == 21)
}
@Test func GroupChatTerminalTurnRejectsLateEvents() {
    var state = started()
    apply(.messageStart(message(101,21)), &state)
    apply(.turnDone(status: .stopped, usage: nil, messageIDs: [100,101]), &state)
    apply(.messageStart(message(102,22)), &state)
    apply(.delta(messageID: 101, memberID: 21, text: "迟到"), &state)
    apply(.turnStart(userMessage: message(100,nil,"讨论",.completed), speakerMemberIDs: [21]), &state)
    #expect(state.status == .stopped && state.messages.count == 2)
    #expect(state.messages.last?.content == "")
}
@Test func GroupChatSnapshotRestoresWithoutReplayingDelta() throws {
    var state = started()
    apply(.messageStart(message(101,21)), &state)
    apply(.delta(messageID: 101, memberID: 21, text: "局部"), &state)
    let body = #"{"id":9,"group_id":7,"client_request_id":"11111111-1111-1111-1111-111111111111","mode":"single","status":"completed","cancel_requested":false,"messages":[{"id":100,"group_id":7,"turn_id":9,"role":"user","content":"讨论","status":"completed"},{"id":101,"group_id":7,"turn_id":9,"member_id":21,"role":"bot","content":"服务器完整答案","status":"completed"}]}"#
    GroupChatReducer.restore(try JSONDecoder().decode(GroupTurn.self, from: Data(body.utf8)), to: &state)
    apply(.delta(messageID: 101, memberID: 21, text: "局部"), &state)
    #expect(state.messages.count == 2 && state.messages.last?.content == "服务器完整答案")
    #expect(state.status == .completed)
}
