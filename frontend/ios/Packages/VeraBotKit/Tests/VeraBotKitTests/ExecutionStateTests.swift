import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

// EXEC-01~：执行状态机。trace JSON 与后端 agents/runtime.py 的 tool_start / tool_result 同形。
private func trace(_ json: String) -> ToolTrace {
    try! JSONDecoder().decode(ToolTrace.self, from: Data(json.utf8))
}
private let weatherStart = trace(#"{"id":"c1","name":"get_weather","args":{"city":"石家庄"}}"#)
private let weatherResult = trace(#"{"id":"c1","name":"get_weather","args":{"city":"石家庄"},"result":{"city":"石家庄"}}"#)
private let askStart = trace(#"{"id":"c2","name":"ask_bot","args":{"bot_name":"小研","question":"q"}}"#)
private let askResult = trace(#"{"id":"c2","name":"ask_bot","args":{"bot_name":"小研","question":"q"},"result":{"answer":"a","delegation_id":3}}"#)
private let rememberStart = trace(#"{"id":"c3","name":"remember","args":{"content":"不吃香菜"}}"#)
private func rememberResult(id: Int = 42, status: String = "proposed", callID: String = "c3") -> ToolTrace {
    trace(#"{"id":"\#(callID)","name":"remember","args":{"content":"不吃香菜"},"result":{"memory_id":\#(id),"status":"\#(status)","action":"create","content":"不吃香菜","type":"preference","scope":"global","sensitive":false}}"#)
}

private func run(_ events: [ExecutionEvent]) -> ExecutionStateMachine {
    var m = ExecutionStateMachine()
    m.send(contentsOf: events)
    return m
}

@Test func execStartsIdleAndSendThinks() {
    var m = ExecutionStateMachine()
    #expect(m.state == .idle)
    #expect(!m.state.isActive)
    m.send(.sent)
    #expect(m.state == .thinking)
    #expect(m.state.isActive)
}

@Test func execPlainReplyCompletes() {
    var m = run([.sent, .delta("你"), .delta("好")])
    #expect(m.state == .replying)
    m.send(.done)
    #expect(m.state == .completed)
    m.send(.reset)
    #expect(m.state == .idle)
}

@Test func execEmptyDeltaKeepsThinking() {
    #expect(run([.sent, .delta("")]).state == .thinking)
}

@Test func execToolCallThenThinkingThenReply() {
    var m = run([.sent, .toolStart(weatherStart)])
    #expect(m.state == .callingTool(name: "get_weather"))
    m.send(.toolResult(weatherResult))
    #expect(m.state == .thinking)           // 工具返回后模型继续处理
    m.send(.delta("晴"))
    #expect(m.state == .replying)
    m.send(.done)
    #expect(m.state == .completed)
}

@Test func execTextBeforeToolThenTool() {
    // 后端同一轮可能先出字再调工具
    let m = run([.sent, .delta("我查一下"), .toolStart(weatherStart)])
    #expect(m.state == .callingTool(name: "get_weather"))
}

@Test func execDelegationUsesBotName() {
    var m = run([.sent, .toolStart(askStart)])
    #expect(m.state == .delegating(botName: "小研"))
    m.send(.toolResult(askResult))
    #expect(m.state == .thinking)
}

@Test func execDelegationWithoutBotName() {
    let t = trace(#"{"id":"c9","name":"ask_bot","args":{"question":"q"}}"#)
    #expect(run([.sent, .toolStart(t)]).state == .delegating(botName: ""))
}

@Test func execOverlappingToolsFallBackToLatestOpen() {
    var m = run([.sent, .toolStart(weatherStart), .toolStart(askStart)])
    #expect(m.state == .delegating(botName: "小研"))
    m.send(.toolResult(askResult))
    #expect(m.state == .callingTool(name: "get_weather"))
    m.send(.toolResult(weatherResult))
    #expect(m.state == .thinking)
}

@Test func execToolResultWithoutStart() {
    #expect(run([.sent, .toolResult(weatherResult)]).state == .thinking)
}

@Test func execMemoryProposalAwaitsConfirmation() {
    var m = run([.sent, .toolStart(rememberStart)])
    #expect(m.state == .callingTool(name: "remember"))
    m.send(contentsOf: [.toolResult(rememberResult()), .delta("要我记住吗？"), .done])
    #expect(m.state == .awaitingConfirmation)
    #expect(m.pendingConfirmations == [42])
    m.send(.confirmationResolved(memoryID: 7))   // 其他卡片：忽略
    #expect(m.state == .awaitingConfirmation)
    m.send(.confirmationResolved(memoryID: 42))
    #expect(m.state == .idle)
    #expect(m.pendingConfirmations.isEmpty)
}

@Test func execMultipleProposalsNeedAllResolved() {
    var m = run([.sent, .toolResult(rememberResult(id: 1, callID: "a")), .toolResult(rememberResult(id: 2, callID: "b")),
                 .delta("x"), .done])
    #expect(m.state == .awaitingConfirmation)
    m.send(.confirmationResolved(memoryID: 1))
    #expect(m.state == .awaitingConfirmation)
    m.send(.confirmationResolved(memoryID: 2))
    #expect(m.state == .idle)
}

@Test func execNonCardMemoryResultCompletes() {
    let m = run([.sent, .toolResult(rememberResult(status: "already_known")), .delta("记得"), .done])
    #expect(m.state == .completed)
    #expect(m.pendingConfirmations.isEmpty)
}

@Test func execErrorThenDoneStaysFailed() {
    // 后端出错时先发 error 再发 done
    var m = run([.sent, .toolStart(weatherStart), .error("模型超时")])
    #expect(m.state == .failed(message: "模型超时"))
    m.send(.done)
    #expect(m.state == .failed(message: "模型超时"))
    m.send(.streamEnded)
    #expect(m.state == .failed(message: "模型超时"))
}

@Test func execErrorBeatsPendingConfirmation() {
    let m = run([.sent, .toolResult(rememberResult()), .error("x"), .done])
    #expect(m.state == .failed(message: "x"))
}

@Test func execStreamEndedWithoutDone() {
    #expect(run([.sent, .delta("半句"), .streamEnded]).state == .completed)
    #expect(run([.sent, .toolResult(rememberResult()), .streamEnded]).state == .awaitingConfirmation)
}

@Test func execStaleEventsIgnoredWhenNotActive() {
    let idle = run([.delta("x"), .toolStart(weatherStart), .error("e"), .done])
    #expect(idle.state == .idle)
    let done = run([.sent, .delta("a"), .done, .delta("late"), .toolStart(askStart), .error("late")])
    #expect(done.state == .completed)
}

@Test func execNewSendClearsPreviousTurn() {
    var m = run([.sent, .toolResult(rememberResult()), .done])
    #expect(m.state == .awaitingConfirmation)
    m.send(.sent)
    #expect(m.state == .thinking)
    #expect(m.pendingConfirmations.isEmpty)
    m.send(.done)
    #expect(m.state == .completed)
    m.send(contentsOf: [.sent, .error("e")])
    m.send(.sent)
    #expect(m.state == .thinking)
}

@Test func execResetFromAnyState() {
    for events in [[ExecutionEvent.sent], [.sent, .toolStart(askStart)], [.sent, .error("e")],
                   [.sent, .toolResult(rememberResult()), .done]] {
        var m = run(events)
        m.send(.reset)
        #expect(m == ExecutionStateMachine())
    }
}

@Test func execChatEventMapping() {
    #expect(ChatEvent.delta("a").executionEvent == .delta("a"))
    #expect(ChatEvent.toolStart(weatherStart).executionEvent == .toolStart(weatherStart))
    #expect(ChatEvent.toolResult(weatherResult).executionEvent == .toolResult(weatherResult))
    #expect(ChatEvent.error("e").executionEvent == .error("e"))
    #expect(ChatEvent.done(ChatDone()).executionEvent == .done)
}
