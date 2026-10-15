import Foundation
import Testing
@testable import VeraBotCore

private func numberedLines(_ n: Int, prefix: String = "第") -> [String] {
    (1...n).map { "\(prefix)\($0)行" }
}

// MARK: - 阈值

@Test func shortRepliesDoNotCollapse() {
    #expect(!LongReplyCollapse.shouldCollapse(""))
    #expect(!LongReplyCollapse.shouldCollapse("好的，明天八点提醒你。"))
    #expect(LongReplyCollapse.preview("好的，明天八点提醒你。") == nil)
    // 恰好等于阈值不折叠
    #expect(!LongReplyCollapse.shouldCollapse(String(repeating: "a", count: LongReplyCollapse.collapseCharacters)))
    #expect(!LongReplyCollapse.shouldCollapse(numberedLines(LongReplyCollapse.collapseLines).joined(separator: "\n")))
}

@Test func longRepliesCollapseByCharactersOrLines() {
    #expect(LongReplyCollapse.shouldCollapse(String(repeating: "a", count: LongReplyCollapse.collapseCharacters + 1)))
    #expect(LongReplyCollapse.shouldCollapse(numberedLines(LongReplyCollapse.collapseLines + 1).joined(separator: "\n")))
    // \r\n 换行同样计行
    #expect(LongReplyCollapse.shouldCollapse(numberedLines(LongReplyCollapse.collapseLines + 1).joined(separator: "\r\n")))
}

// MARK: - 中文（CJK）

@Test func cjkCountsCharactersNotBytes() throws {
    // 1000 个汉字 = 3000 个 UTF-8 字节，但只有 1000 字，不折叠
    let below = String(repeating: "长", count: 1000)
    #expect(below.utf8.count > LongReplyCollapse.collapseCharacters)
    #expect(!LongReplyCollapse.shouldCollapse(below))

    let source = String(repeating: "今天天气晴朗适合出门散步。", count: 130)   // 1690 字、无换行
    #expect(LongReplyCollapse.shouldCollapse(source))
    let preview = try #require(LongReplyCollapse.preview(source))
    #expect(preview.count == LongReplyCollapse.previewCharacters + 1)
    #expect(preview.hasSuffix("…"))
    #expect(source.hasPrefix(String(preview.dropLast())))
}

// MARK: - 截断位置

@Test func previewCutsAtLineBoundaryByLineLimit() {
    let lines = numberedLines(60)
    let preview = LongReplyCollapse.preview(lines.joined(separator: "\n"))
    #expect(preview == lines.prefix(LongReplyCollapse.previewLines).joined(separator: "\n"))
}

@Test func previewCutsAtLineBoundaryByCharacterLimit() {
    let line = String(repeating: "字", count: 100)
    let source = Array(repeating: line, count: 20).joined(separator: "\n")
    // 3 行正好 300 字，第 4 行放不下且已收内容超过一半：停在行尾，不补「…」
    #expect(LongReplyCollapse.preview(source) == Array(repeating: line, count: 3).joined(separator: "\n"))
}

@Test func previewCutsInsideLineOnlyWhenTooLittleKept() throws {
    let long = String(repeating: "很", count: 2000)
    let preview = try #require(LongReplyCollapse.preview("结论：\n" + long))
    #expect(preview == "结论：\n" + String(repeating: "很", count: LongReplyCollapse.previewCharacters - 3) + "…")
}

@Test func previewSkipsLeadingBlankLinesAndHandlesCRLF() {
    let lines = numberedLines(50)
    let preview = LongReplyCollapse.preview("\n  \n" + lines.joined(separator: "\r\n"))
    #expect(preview == lines.prefix(LongReplyCollapse.previewLines).joined(separator: "\n"))
}

// MARK: - 代码块

@Test func previewBacksOutOfOpenCodeFence() {
    let code = (1...60).map { "print(\($0))" }
    let source = "示例如下：\n\n```swift\n" + code.joined(separator: "\n") + "\n```\n结束"
    #expect(LongReplyCollapse.preview(source) == "示例如下：")
}

@Test func previewKeepsClosedFenceAndClosesLeadingFence() throws {
    // 已闭合的短代码块完整保留
    let closed = "看：\n```\nlet a = 1\n```\n" + numberedLines(50).joined(separator: "\n")
    let p1 = try #require(LongReplyCollapse.preview(closed))
    #expect(p1.hasPrefix("看：\n```\nlet a = 1\n```\n第1行"))
    #expect(p1.components(separatedBy: "\n").count == LongReplyCollapse.previewLines)

    // 回复以代码块开头：保留前几行代码并补闭合 ```
    let code = (1...60).map { "line \($0)" }
    let p2 = try #require(LongReplyCollapse.preview("```python\n" + code.joined(separator: "\n") + "\n```"))
    let rows = p2.components(separatedBy: "\n")
    #expect(rows.first == "```python")
    #expect(rows.last == "```")
    #expect(rows.filter { $0.hasPrefix("```") }.count == 2)
    #expect(MessageMarkdown.blocks(p2) == [.code(language: "python", code: code.prefix(LongReplyCollapse.previewLines - 1).joined(separator: "\n"))])
}

// MARK: - 字素（Grapheme）

@Test func previewNeverSplitsGraphemes() throws {
    let family = "👨‍👩‍👧‍👦"
    let accented = "e\u{301}"
    for unit in [family, accented, "🇨🇳"] {
        let source = String(repeating: unit, count: 2000)
        let preview = try #require(LongReplyCollapse.preview(source))
        #expect(preview == String(repeating: unit, count: LongReplyCollapse.previewCharacters) + "…")
        #expect(preview.dropLast().allSatisfy { String($0) == unit })
    }
}
