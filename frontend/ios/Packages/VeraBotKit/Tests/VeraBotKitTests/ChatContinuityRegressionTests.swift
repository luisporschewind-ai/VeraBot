import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

/// 2026-10-15：bytes.lines 吞空行导致 SSE 事件不派发，失败任务在客户端一直「排队中」。
@Test func durableParserEmitsPreviousEventWhenBlankLinesAreDropped() {
    var parser = DurableSSEParser()
    let lines = ["id: 30", "event: error", "data: {\"message\":\"x\"}",
                 "id: 31", "event: task_updated", "data: {\"state\":\"failed\"}",
                 "id: 32", "event: done", "data: {}"]
    var events: [DurableEvent] = []
    for line in lines { if let e = parser.line(line) { events.append(e) } }
    #expect(events.map(\.id) == [30, 31])
    #expect(events.map(\.name) == ["error", "task_updated"])
    #expect(parser.line("").map(\.id) == 32)
}

@Test func durableParserStillUsesBlankLineTerminator() {
    var parser = DurableSSEParser()
    #expect(parser.line("id: 5") == nil)
    #expect(parser.line("event: done") == nil)
    #expect(parser.line("data: {}") == nil)
    #expect(parser.line(": keepalive") == nil)
    let event = parser.line("")
    #expect(event?.id == 5 && event?.name == "done")
}

@Test func readingDividerOnlyOnEntryOrResume() {
    var reading = ConversationReadingSession()
    reading.enter([MessagePublication(messageID: 12, publicationRevision: 1), MessagePublication(messageID: 10, publicationRevision: 1)])
    #expect(reading.dividerMessageID == 10)
    // 正在看对话时到达的回复不移动、不新增分隔线
    reading.include([MessagePublication(messageID: 20, publicationRevision: 1)])
    #expect(reading.dividerMessageID == 10)
    reading.leave()
    #expect(reading.dividerMessageID == nil)
    // 已读后再次进入：没有未读，就没有分隔线
    reading.enter([])
    #expect(reading.dividerMessageID == nil)
    reading.include([MessagePublication(messageID: 30, publicationRevision: 1)])
    #expect(reading.dividerMessageID == nil)
    // 从后台回来：期间到达的未读回复上方显示一次
    reading.resume([MessagePublication(messageID: 31, publicationRevision: 1)])
    #expect(reading.dividerMessageID == 31)
    reading.resume([MessagePublication(messageID: 40, publicationRevision: 1)])
    #expect(reading.dividerMessageID == 31)
}

/// 2026-10-15：打开对话后再次进入仍显示未读。进入即上报全部未读（去重、取最高修订）。
@Test func entryReadBatchCoversAllUnreadMessages() throws {
    let json = """
    {"kind":"private","conversation_id":7,"generation":2,"revision":9,"state":"idle","phase":"","unread_count":3,"pending_count":0,
     "unread_messages":[{"message_id":12,"publication_revision":1},{"message_id":10,"publication_revision":1},{"message_id":12,"publication_revision":3}],
     "work_items":[],"latest_message":null}
    """
    let activity = try JSONDecoder().decode(ConversationActivity.self, from: Data(json.utf8))
    #expect(activity.entryReadBatch == [MessagePublication(messageID: 10, publicationRevision: 1), MessagePublication(messageID: 12, publicationRevision: 3)])
    // 已全部读过：再次进入没有未读，也就没有分隔线
    var reading = ConversationReadingSession()
    reading.enter([])
    #expect(reading.dividerMessageID == nil)
}

private func activityRow(state: String, phase: String, workItems: String, latest: String?) throws -> ConversationActivity {
    let json = """
    {"kind":"private","conversation_id":7,"generation":1,"revision":40,"state":"\(state)","phase":"\(phase)","unread_count":1,"pending_count":0,
     "unread_messages":[],"work_items":[\(workItems)],"latest_message":\(latest.map { "{\"id\":52,\"content\":\"\($0)\",\"created_at\":\"2026-10-15T03:00:00+00:00\"}" } ?? "null")}
    """
    return try JSONDecoder().decode(ConversationActivity.self, from: Data(json.utf8))
}

/// 2026-10-15：私聊发问后立刻回列表，Bot 已正常回复，列表行却显示「工作暂未完成」。
/// 服务端摘要保留本代历史上 interrupted 的旧任务，最新任务 completed 后 state 落回那条旧记录。
@Test func listRowShowsReplyPreviewOverStaleInterruptedWork() throws {
    let stale = #"{"id":3,"state":"interrupted","phase":"interrupted","version":2,"wait_id":null,"source":"chat"}"#
    let running = #"{"id":9,"state":"running","phase":"retry_wait","version":1,"wait_id":null,"source":"chat"}"#
    let during = try activityRow(state: "running", phase: "retry_wait", workItems: "\(stale),\(running)", latest: "帮我查一下天气")
    #expect(during.statusText == "正在思考")
    let done = try activityRow(state: "interrupted", phase: "interrupted", workItems: stale, latest: "明天晴，最高 22 度。")
    #expect(done.displayState == "idle" && done.displayPhase == "idle")
    #expect(done.statusText == "")
    #expect(!done.hasNewlyFailedWork(since: during))
    // 没有任何可读消息时才用状态短句兜底
    let empty = try activityRow(state: "interrupted", phase: "interrupted", workItems: stale, latest: nil)
    #expect(empty.statusText == "工作暂未完成")
    // 当前这一轮真的失败：列表显示失败正文预览，但不算成功完成
    let failed = try activityRow(state: "failed", phase: "failed", workItems: "\(stale),{\"id\":9,\"state\":\"failed\",\"phase\":\"failed\",\"version\":1,\"wait_id\":null,\"source\":\"chat\"}", latest: "回复暂时无法完成")
    #expect(failed.statusText == "")
    #expect(failed.hasNewlyFailedWork(since: during))
    // 等待用户的状态是可操作的，仍然显示
    let waiting = try activityRow(state: "awaiting_user", phase: "awaiting_user", workItems: stale, latest: "要查哪个城市？")
    #expect(waiting.statusText == "等你补充")
}

@Test func groupListDoesNotAskUserForMoreInformation() throws {
    func activity(kind: String) throws -> ConversationActivity {
        try JSONDecoder().decode(ConversationActivity.self, from: Data("""
        {"kind":"\(kind)","conversation_id":1,"generation":1,"revision":1,"state":"awaiting_user","phase":"awaiting_user","unread_count":0,"pending_count":1,"unread_messages":[],"work_items":[]}
        """.utf8))
    }
    #expect(try activity(kind:"group").statusText.isEmpty)
    #expect(try activity(kind:"private").statusText == "等你补充")
}
