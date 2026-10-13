import Foundation
import Testing
import VeraBotCore
@testable import VeraBotNetworking

private let groupUser = #"{"id":100,"group_id":7,"turn_id":9,"member_id":null,"role":"user","content":"一起聊聊","status":"completed"}"#
private let groupBot = #"{"id":101,"group_id":7,"turn_id":9,"member_id":21,"role":"bot","content":"你好","status":"completed"}"#
@Test func GroupChatAllEventFixturesDecode() throws {
    let payloads: [(String, String)] = [
        ("turn_start", "\"user_message\":\(groupUser),\"speaker_member_ids\":[21,22]"),
        ("message_start", "\"message\":\(groupBot.replacingOccurrences(of: "completed", with: "streaming"))"),
        ("status", #""message_id":101,"member_id":21,"phase":"thinking""#),
        ("delta", #""message_id":101,"member_id":21,"text":"你好""#),
        ("message_done", "\"message\":\(groupBot)"),
        ("error", #""code":"provider_error","message":"暂时不能回应","message_id":101"#),
        ("turn_done", #""status":"partial","usage":null,"message_ids":[100,101]"#)
    ]
    for (name, fields) in payloads {
        let event = GroupChatEventParser.parse(event: name, data: Data("{\"group_id\":7,\"turn_id\":9,\(fields)}".utf8))
        #expect(event != nil, "Missing event: \(name)")
        #expect(event?.groupID == 7)
        #expect(event?.turnID == 9)
    }
}
@Test func GroupChatRejectsMissingOrMismatchedIdentity() {
    for body in [#"{"turn_id":9,"message_id":101,"member_id":21,"text":"x"}"#,
                 #"{"group_id":7,"turn_id":9,"text":"x"}"#,
                 #"{"group_id":7,"turn_id":9,"message_id":101,"text":"x"}"#] {
        #expect(GroupChatEventParser.parse(event: "delta", data: Data(body.utf8)) == nil)
    }
    let bad = "{\"group_id\":8,\"turn_id\":9,\"message\":\(groupBot)}"
    #expect(GroupChatEventParser.parse(event: "message_done", data: Data(bad.utf8)) == nil)
    #expect(GroupChatEventParser.parse(event: "future_event", data: Data("{}".utf8)) == nil)
}
@Test func GroupChatDeletedMembersDecode() throws {
    let data = Data(##"{"id":7,"name":"伙伴","default_bot_id":null,"read_only":true,"members":[{"id":21,"bot_id":null,"name":"旧伙伴","color":"#6461D1","detail":"","avatar":"robot","appearance":null,"available":false}]}"##.utf8)
    let group = try JSONDecoder().decode(ChatGroup.self, from: data)
    #expect(group.readOnly)
    #expect(group.members[0].botID == nil && !group.members[0].available)
}
@Test func GroupChatRequestPreservesIDAndOmitsUnsetTarget() throws {
    let request = GroupChatRequest(message: "讨论", mode: .round)
    let body = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(body["client_request_id"] as? String == request.clientRequestID.uuidString)
    #expect(body["mode"] as? String == "round")
    #expect(body["target_bot_id"] == nil)
    let patch = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(GroupUpdateRequest(name: "新名称"))) as? [String: Any])
    #expect(patch["default_bot_id"] == nil)
}

@Test func GroupChatSSEPreservesBlankSeparatorsAndMultilineData() {
    var parser = GroupSSEDecoder()
    let lines = [": heartbeat", "event: delta", "data: {\"group_id\":7,\"turn_id\":9,",
                 "data: \"message_id\":101,\"member_id\":21,\"text\":\"你好\"}"]
    for line in lines { #expect(parser.consume(line) == nil) }
    let result = parser.consume("")
    #expect(result?.payload == .delta(messageID: 101, memberID: 21, text: "你好"))
    #expect(parser.consume("") == nil)
}

@Test func GroupChatRetryStartsNewTurnWithOriginalQuestion() {
    let body = #"{"group_id":7,"turn_id":10,"user_message":{"id":100,"group_id":7,"turn_id":9,"role":"user","content":"原问题","status":"completed"},"speaker_member_ids":[21]}"#
    let event = GroupChatEventParser.parse(event: "turn_start", data: Data(body.utf8))
    #expect(event != nil)
    var state = GroupChatState(groupID: 7)
    if let event { GroupChatReducer.apply(event, to: &state) }
    #expect(state.activeTurnID == 10 && state.messages.first?.id == 100)
}
