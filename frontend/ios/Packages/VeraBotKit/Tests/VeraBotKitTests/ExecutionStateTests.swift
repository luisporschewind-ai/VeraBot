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
    #expect(m.state == .delegating(botName: "小研", progress: nil))
    m.send(.toolResult(askResult))
    #expect(m.state == .thinking)
}

@Test func execDelegationWithoutBotName() {
    let t = trace(#"{"id":"c9","name":"ask_bot","args":{"question":"q"}}"#)
    #expect(run([.sent, .toolStart(t)]).state == .delegating(botName: "", progress: nil))
}

@Test func execOverlappingToolsFallBackToLatestOpen() {
    var m = run([.sent, .toolStart(weatherStart), .toolStart(askStart)])
    #expect(m.state == .delegating(botName: "小研", progress: nil))
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
    let st = ChatStatus(phase: "recalling", depth: 0, botName: "Vera")
    #expect(ChatEvent.status(st).executionEvent == .status(st))
}

// MARK: - status 事件 / 委派进度 / 短暂受阻 (EXEC-20~)

private func status(_ json: String) -> ChatStatus {
    try! JSONDecoder().decode(ChatStatus.self, from: Data(json.utf8))
}
private let recallingStatus = status(#"{"phase":"recalling","depth":0,"bot_name":"Vera","tool":null,"parent_id":null}"#)
private let bThinking = status(#"{"phase":"thinking","depth":1,"bot_name":"小研","tool":null,"parent_id":"c2"}"#)
private let bTool = status(#"{"phase":"tool","depth":1,"bot_name":"小研","tool":"get_weather","parent_id":"c2"}"#)
private let cThinking = status(#"{"phase":"thinking","depth":2,"bot_name":"阿厨","tool":null,"parent_id":"c2"}"#)

@Test func execStatusDecodesBackendPayload() {
    #expect(recallingStatus.knownPhase == .recalling)
    #expect(bTool == ChatStatus(phase: "tool", depth: 1, botName: "小研", tool: "get_weather", parentID: "c2"))
    let partial = status(#"{"phase":"future_phase"}"#)       // 缺字段 / 未知阶段
    #expect(partial.depth == 0 && partial.botName == nil && partial.knownPhase == nil)
    #expect(Set(ChatStatus.Phase.allCases.map(\.rawValue)) == ["recalling", "thinking", "tool"])
}

@Test func execSSEParsesStatusEvent() {
    let data = Data(#"{"phase":"thinking","depth":1,"bot_name":"小研","tool":null,"parent_id":"c2"}"#.utf8)
    guard case .status(let s)? = APIClient.parse(event: "status", data: data) else {
        Issue.record("status 未解析"); return
    }
    #expect(s == bThinking)
    #expect(APIClient.parse(event: "unknown_event", data: data) == nil)
}

@Test func execRecallingThenReply() {
    var m = run([.sent, .status(recallingStatus)])
    #expect(m.state == .recalling)
    #expect(m.state.isActive)
    m.send(.delta("好"))
    #expect(m.state == .replying)
    m.send(.done)
    #expect(m.state == .completed)
}

@Test func execRecallingIgnoredAfterOutputStarts() {
    #expect(run([.sent, .delta("a"), .status(recallingStatus)]).state == .replying)
    #expect(run([.sent, .status(recallingStatus), .toolStart(weatherStart)]).state == .callingTool(name: "get_weather"))
}

@Test func execDelegationProgressUpdates() {
    var m = run([.sent, .toolStart(askStart), .status(bThinking)])
    #expect(m.state == .delegating(botName: "小研", progress: DelegationProgress(botName: "小研", depth: 1)))
    m.send(.status(bTool))
    #expect(m.state == .delegating(botName: "小研", progress: DelegationProgress(botName: "小研", depth: 1, tool: "get_weather")))
    m.send(.status(cThinking))
    #expect(m.state == .delegating(botName: "小研", progress: DelegationProgress(botName: "阿厨", depth: 2)))
    m.send(.toolResult(askResult))
    #expect(m.state == .thinking)
}

@Test func execDelegationStatusWithUnknownParentIgnored() {
    let other = status(#"{"phase":"thinking","depth":1,"bot_name":"X","tool":null,"parent_id":"nope"}"#)
    let m = run([.sent, .toolStart(askStart), .status(other)])
    #expect(m.state == .delegating(botName: "小研", progress: nil))
    // 指向非委派工具的 parent_id 也忽略
    let toWeather = status(#"{"phase":"thinking","depth":1,"bot_name":"X","tool":null,"parent_id":"c1"}"#)
    #expect(run([.sent, .toolStart(weatherStart), .status(toWeather)]).state == .callingTool(name: "get_weather"))
}

@Test func execUnknownStatusPhaseIgnored() {
    let m = run([.sent, .status(status(#"{"phase":"future_phase","depth":0}"#))])
    #expect(m.state == .thinking)
}

private let rejectedAsk = trace(#"{"id":"c2","name":"ask_bot","args":{"bot_name":"小研","question":"q"},"result":{"error":"「小研」不接受其他 Bot 的委派","code":"target_refuses","delegation_id":5}}"#)
private let deniedTool = trace(#"{"id":"c1","name":"get_weather","args":{},"result":{"error":"当前 Bot 未被授权使用该能力","code":"tool_not_allowed"}}"#)
private let failedTool = trace(#"{"id":"c1","name":"get_weather","args":{},"result":{"error":"工具执行失败: Timeout"}}"#)

@Test func execRejectedDelegationBlocksThenResumes() {
    var m = run([.sent, .toolStart(askStart), .toolResult(rejectedAsk)])
    #expect(m.state == .blocked(code: "target_refuses", message: "「小研」不接受其他 Bot 的委派"))
    #expect(m.state.isActive)
    let serial = m.blockedSerial
    m.send(.blockedElapsed(serial: serial))
    #expect(m.state == .thinking)
}

@Test func execAllRejectCodesBlock() {
    for code in ["self", "loop", "not_in_allowlist", "target_refuses", "turn_cap", "budget",
                 "unknown_tool", "tool_not_allowed", "max_depth", "memory_not_delegable", "memory_disabled"] {
        let t = trace(#"{"id":"c1","name":"get_weather","args":{},"result":{"error":"x","code":"\#(code)"}}"#)
        #expect(run([.sent, .toolResult(t)]).state == .blocked(code: code, message: "x"))
    }
    #expect(run([.sent, .toolResult(deniedTool)]).state == .blocked(code: "tool_not_allowed", message: "当前 Bot 未被授权使用该能力"))
    #expect(run([.sent, .toolResult(failedTool)]).state == .blocked(code: nil, message: "工具执行失败: Timeout"))
}

@Test func execSuccessfulResultsDoNotBlock() {
    #expect(ExecutionStateMachine.failure(of: weatherResult) == nil)
    #expect(ExecutionStateMachine.failure(of: askResult) == nil)
    #expect(ExecutionStateMachine.failure(of: rememberResult()) == nil)
    let nullError = trace(#"{"id":"c1","name":"get_weather","args":{},"result":{"error":null}}"#)
    #expect(ExecutionStateMachine.failure(of: nullError) == nil)
    #expect(ExecutionStateMachine.failure(of: weatherStart) == nil)   // result 为 nil
}

@Test func execBlockedLeftEarlyByNextEvent() {
    #expect(run([.sent, .toolResult(deniedTool), .delta("抱歉")]).state == .replying)
    #expect(run([.sent, .toolResult(deniedTool), .toolStart(askStart)]).state == .delegating(botName: "小研", progress: nil))
    #expect(run([.sent, .toolResult(deniedTool), .done]).state == .completed)
    #expect(run([.sent, .toolResult(deniedTool), .error("e")]).state == .failed(message: "e"))
}

@Test func execStaleBlockedElapsedIgnored() {
    var m = run([.sent, .toolResult(deniedTool)])
    let first = m.blockedSerial
    m.send(.toolResult(failedTool))                 // 第二次受阻
    #expect(m.blockedSerial == first + 1)
    m.send(.blockedElapsed(serial: first))          // 旧计时器：忽略
    #expect(m.state == .blocked(code: nil, message: "工具执行失败: Timeout"))
    m.send(.blockedElapsed(serial: first + 1))
    #expect(m.state == .thinking)
    m.send(.blockedElapsed(serial: first + 1))      // 非 blocked：忽略
    #expect(m.state == .thinking)
}

@Test func execBlockedResumesToOpenDelegation() {
    // 委派中另一个工具失败（并行情形）：受阻结束后回到委派，期间的进度也会保留
    var m = run([.sent, .toolStart(askStart), .toolStart(weatherStart), .toolResult(deniedTool)])
    #expect(m.state == .blocked(code: "tool_not_allowed", message: "当前 Bot 未被授权使用该能力"))
    m.send(.status(bThinking))
    #expect(m.state == .blocked(code: "tool_not_allowed", message: "当前 Bot 未被授权使用该能力"))
    m.send(.blockedElapsed(serial: m.blockedSerial))
    #expect(m.state == .delegating(botName: "小研", progress: DelegationProgress(botName: "小研", depth: 1)))
}

@Test func execResetCancelsBlockedTimer() {
    var c = ExecutionAvatarController()
    _ = c.send(.sent)
    let started = c.send(.toolResult(deniedTool))
    #expect(started == [.startBlocked(serial: 1)])
    let reset = c.send(.reset)
    #expect(reset == [.cancelBlocked])
    #expect(c.state == .idle)
    #expect(c.blockedFired(serial: 1).isEmpty)
    #expect(c.state == .idle)
}

@Test func execCompletedReturnsToIdleAfterDelay() {
    var c = ExecutionAvatarController()
    _ = c.send(.sent)
    _ = c.send(.delta("好"))
    let done = c.send(.done)
    #expect(c.state == .completed)
    #expect(done == [.startIdle])
    #expect(ExecutionStateMachine.completedIdleDelay == .milliseconds(1500))
    #expect(ExecutionStateMachine.blockedDisplayDuration == .milliseconds(1200))
    let back = c.idleFired()
    #expect(c.state == .idle)
    #expect(back == [.cancelIdle])
    #expect(c.idleFired().isEmpty)
}

@Test func execResetAndSendCancelIdleTimer() {
    var c = ExecutionAvatarController()
    _ = c.send(.sent)
    _ = c.send(.delta("好"))
    _ = c.send(.done)
    let reset = c.send(.reset)
    #expect(reset == [.cancelIdle])
    #expect(c.idleFired().isEmpty)
    #expect(c.state == .idle)

    _ = c.send(.sent)
    _ = c.send(.delta("好"))
    _ = c.send(.done)
    let again = c.send(.sent)
    #expect(again == [.cancelIdle])
    #expect(c.state == .thinking)
    #expect(c.idleFired().isEmpty)
    #expect(c.state == .thinking)
}

@Test func execAwaitingConfirmationAndFailureDoNotArmIdle() {
    var waiting = ExecutionAvatarController()
    _ = waiting.send(.sent)
    _ = waiting.send(.toolResult(rememberResult()))
    let done = waiting.send(.done)
    #expect(waiting.state == .awaitingConfirmation)
    #expect(!done.contains(.startIdle))
    #expect(waiting.idleFired().isEmpty)
    #expect(waiting.state == .awaitingConfirmation)

    var failed = ExecutionAvatarController()
    _ = failed.send(.sent)
    let err = failed.send(.error("网络异常"))
    #expect(failed.state == .failed(message: "网络异常"))
    #expect(!err.contains(.startIdle))
}

@Test func execLeavingBlockedCancelsTimer() {
    var c = ExecutionAvatarController()
    _ = c.send(.sent)
    _ = c.send(.toolResult(deniedTool))
    let next = c.send(.delta("抱歉"))
    #expect(next == [.cancelBlocked])
    #expect(c.state == .replying)
    #expect(c.blockedFired(serial: 1).isEmpty)
    #expect(c.state == .replying)
}

@Test func execSecondBlockReplacesTimer() {
    var c = ExecutionAvatarController()
    _ = c.send(.sent)
    _ = c.send(.toolResult(deniedTool))
    let second = c.send(.toolResult(failedTool))
    #expect(second == [.cancelBlocked, .startBlocked(serial: 2)])
    #expect(c.blockedFired(serial: 1).isEmpty)
    let resume = c.blockedFired(serial: 2)
    #expect(resume == [.cancelBlocked])
    #expect(c.state == .thinking)
}

@Test func execDoneWhileBlockedSwitchesToIdleTimer() {
    var c = ExecutionAvatarController()
    _ = c.send(.sent)
    _ = c.send(.toolResult(deniedTool))
    let done = c.send(.done)
    #expect(done == [.cancelBlocked, .startIdle])
    #expect(c.state == .completed)
    #expect(c.blockedFired(serial: 1).isEmpty)
    let end = c.send(.streamEnded)
    #expect(end.isEmpty)
    #expect(c.state == .completed)
}

@Test func execFailedRememberResultBlocks() {
    let capped = trace(#"{"id":"c3","name":"remember","args":{"content":"x"},"result":{"error":"本轮提议次数已达上限","code":"proposal_cap"}}"#)
    let m = run([.sent, .toolResult(capped)])
    #expect(m.state == .blocked(code: "proposal_cap", message: "本轮提议次数已达上限"))
    #expect(m.pendingConfirmations.isEmpty)
}
