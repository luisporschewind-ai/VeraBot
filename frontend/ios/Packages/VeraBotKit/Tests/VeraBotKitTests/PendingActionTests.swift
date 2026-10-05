import Testing
import Foundation
@testable import VeraBotCore
@testable import VeraBotNetworking

@Test func pendingActionDecodesREST() throws {
    let json = """
    {"id":51,"kind":"mcp_tool_call","status":"pending","bot_id":3,"server_id":2,
     "server":"GitHub","tool":"mcp__github__create_issue","label":"创建 issue",
     "risk":"write","arguments":{"title":"hi","body":"x"},"warnings":["注意"],
     "expires_at":"2026-10-05T16:00:00+00:00"}
    """
    let a = try JSONDecoder().decode(PendingAction.self, from: Data(json.utf8))
    #expect(a.id == 51)
    #expect(a.toolRisk == .write)
    #expect(a.warnings == ["注意"])
    #expect(a.arguments?.argumentPairs.contains(where: { $0.0 == "title" && $0.1 == "hi" }) == true)
}

@Test func confirmationRequiredDecodesSSE() throws {
    let json = """
    {"action_id":9,"kind":"mcp_tool_call","server":"Learn","server_id":1,
     "tool":"mcp__learn__delete_item","label":"delete_item","arguments":{"id":"1"},
     "risk":"destructive","warnings":[],"expires_at":"2026-10-05T16:00:00+00:00"}
    """
    let c = try JSONDecoder().decode(ConfirmationRequired.self, from: Data(json.utf8))
    #expect(c.actionId == 9)
    #expect(c.toolRisk == .destructive)
    let pending = c.asPending()
    #expect(pending.id == 9 && pending.status == "pending")
}

@Test func toolTracePendingConfirmation() throws {
    let json = """
    {"id":"c1","name":"mcp__learn__delete_item","args":{"id":"x"},
     "result":{"status":"pending_confirmation","action_id":7,"kind":"mcp_tool_call",
               "server":"Learn","tool":"mcp__learn__delete_item","label":"delete_item",
               "arguments":{"id":"x"},"risk":"destructive","warnings":[],
               "expires_at":"2026-10-05T16:00:00+00:00","message":"已请用户确认，尚未执行"}}
    """
    let t = try JSONDecoder().decode(ToolTrace.self, from: Data(json.utf8))
    let p = try #require(t.pendingConfirmation)
    #expect(p.actionId == 7)
    #expect(JSONDecoder().decode(ToolTrace.self, from: Data(#"{"id":"w","name":"get_weather","args":{},"result":{"ok":true}}"#.utf8)).pendingConfirmation == nil)
}

@Test func chatEventParsesConfirmationRequired() {
    let data = Data("""
    {"action_id":3,"kind":"mcp_tool_call","server":"S","tool":"mcp__s__t","label":"t",
     "arguments":{},"risk":"write","warnings":[],"expires_at":"2026-10-05T16:00:00+00:00"}
    """.utf8)
    let ev = APIClient.parse(event: "confirmation_required", data: data)
    guard case .confirmationRequired(let c)? = ev else {
        Issue.record("expected confirmationRequired")
        return
    }
    #expect(c.actionId == 3)
    #expect(APIClient.parse(event: "confirmation_required", data: Data("{}".utf8)) == nil as ChatEvent?)
}

@Test func toolCallsResponseDecodes() throws {
    let json = """
    {"tool_calls":[{"id":1,"kind":"mcp_action_requested","created_at":"2026-10-05T15:00:00+00:00",
      "server":"learn","tool":"delete_item","status":null,"action_id":5,"duration_ms":null}]}
    """
    let r = try JSONDecoder().decode(ToolCallsResponse.self, from: Data(json.utf8))
    #expect(r.toolCalls.count == 1 && r.toolCalls[0].actionId == 5)
}
