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
