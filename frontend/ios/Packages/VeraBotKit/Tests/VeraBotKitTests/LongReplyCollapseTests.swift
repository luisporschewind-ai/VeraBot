import Foundation
import Testing
@testable import VeraBotCore

private func numberedLines(_ n: Int, prefix: String = "第") -> [String] {
    (1...n).map { "\(prefix)\($0)行的补充说明内容" }
}

// MARK: - 真实回复形状（思考助手）

// 与本地库里「思考助手」三条回复同形：标题 + 表格 + 列表 + 空行，594 字 / 24 行、716 字 / 30 行、329 字 / 14 行。
private let decisionReplyLines = [
    "## 结论",
    "",
    "先把目标拆成三步：明确问题、列出约束、再比较方案。你现在的核心矛盾是上线时间紧、预算有限，但又希望流程能长期贴合团队习惯，所以不能只盯着眼前这一点成本。",
    "",
    "### 方案对比",
    "",
    "| 方案 | 优点 | 风险 |",
    "|---|---|---|",
    "| 自己开发 | 完全可控，能贴合现有流程 | 周期长，需要专人长期维护 |",
    "| 采购现成工具 | 上线快，有厂商支持和培训 | 定制困难，年费逐年上涨 |",
    "| 外包定制 | 兼顾速度与贴合度 | 交付质量依赖供应商水平 |",
    "",
    "### 关键考虑",
    "- **时间**：如果三个月内必须上线，自研基本来不及，除非砍掉大部分的功能。",
    "- **预算**：采购年费约等于半个人力成本，外包则是一次性投入加少量维护费。",
    "- **维护**：自研和外包都需要有人长期负责后续迭代，否则半年后就会跟不上业务。",
    "- **数据**：涉及客户隐私的数据最好留在自己的服务器上，选型时要先确认部署方式。",
    "",
    "### 建议",
    "1. 先用现成工具跑通最小流程，验证需求是否真实存在，避免一开始就重投入。",
    "2. 同时整理清楚哪些环节必须定制，估算真实的工作量和需要的人手。",
    "3. 三个月后再根据使用数据决定是否转为自研或外包，到时候判断会更有把握。",
    "",
    "如果你愿意，可以告诉我团队规模和预算上限，我再帮你细化每一步的时间表、负责人安排和验收标准，方便你直接拿去和老板当面讨论。",
]
private let decisionReply = decisionReplyLines.joined(separator: "\n")

private let decisionReplyWithRisks = (Array(decisionReplyLines.prefix(22)) + [
    "",
    "### 风险提示",
    "",
    "- 现成工具的数据导出格式一定要提前确认清楚，避免以后迁移时非常被动和麻烦。",
    "- 外包合同里写清楚源码归属、交付文档和售后期限，验收时按清单逐项核对。",
    "- 不管最后选哪条路，都先指定一位内部负责人，对最终结果和进度负责。",
    "",
    decisionReplyLines[decisionReplyLines.count - 1],
]).joined(separator: "\n")

private let shortAdviceReply = [
    "## 简短回答",
    "",
    "可以开始，但建议先把节奏定下来再慢慢加量，避免一开始就把自己累垮，也更容易坚持下去。",
    "",
    "| 项目 | 建议 |",
    "|---|---|",
    "| 时间 | 每天固定半小时，最好放在早上精力最好的时候，周末可以适当延长 |",
    "| 方式 | 先读后写，边读边记要点，读完一章用自己的话写三句话总结 |",
    "",
    "- 先选一本入门书，读完再换下一本，不要同时开好几本，容易半途而废。",
    "- 每周回顾一次笔记，把没有读懂的地方单独列出来，集中时间解决。",
    "- 遇到卡住的问题，带着具体的段落和你自己的理解来问我，我们一起拆开看。",
    "",
    "坚持两周后再回头看效果，觉得节奏不合适就随时调整，不必勉强，也不用和别人比进度，找到适合自己的节奏最重要，有新的问题或者新的想法随时来找我。",
].joined(separator: "\n")

@Test func realMarkdownRepliesOverOneScreenCollapse() throws {
    // 1500 字 / 40 行的旧阈值下这两条都不折叠（估算约 45 行、57 行，手机上 1.5～2 屏）
    #expect(decisionReply.count == 594)
    #expect(decisionReply.components(separatedBy: "\n").count == 24)
    #expect(decisionReplyWithRisks.count == 716)
    #expect(decisionReplyWithRisks.components(separatedBy: "\n").count == 30)
    #expect(LongReplyCollapse.shouldCollapse(decisionReply))
    #expect(LongReplyCollapse.shouldCollapse(decisionReplyWithRisks))

    // 预览：标题 + 第一段结论，正好 8 行；不带后面的空行和下一个标题
    let expected = decisionReplyLines.prefix(3).joined(separator: "\n")
    #expect(LongReplyCollapse.preview(decisionReply) == expected)
    #expect(LongReplyCollapse.preview(decisionReplyWithRisks) == expected)
}

@Test func realMarkdownReplyUnderOneScreenStaysExpanded() {
    // 估算约 24 行，不到一屏
    #expect(shortAdviceReply.count == 329)
    #expect(shortAdviceReply.components(separatedBy: "\n").count == 14)
    #expect(!LongReplyCollapse.shouldCollapse(shortAdviceReply))
    #expect(LongReplyCollapse.preview(shortAdviceReply) == nil)
}

// MARK: - 阈值

@Test func shortRepliesDoNotCollapse() {
    #expect(!LongReplyCollapse.shouldCollapse(""))
    #expect(!LongReplyCollapse.shouldCollapse("好的，明天八点提醒你。"))
    #expect(LongReplyCollapse.preview("好的，明天八点提醒你。") == nil)
    // 恰好等于阈值不折叠：28 行
    #expect(!LongReplyCollapse.shouldCollapse(Array(repeating: String(repeating: "a", count: 30), count: LongReplyCollapse.collapseRows).joined(separator: "\n")))
    // 恰好 500 加权字：两条 ``` 共 6 个 ASCII（3 字）+ 7 行 × 71 个汉字；代码行不折行，只有 8 行
    let code = Array(repeating: String(repeating: "数", count: 71), count: 7).joined(separator: "\n")
    #expect(!LongReplyCollapse.shouldCollapse("```\n" + code + "\n```"))
    #expect(LongReplyCollapse.shouldCollapse("```\n" + code + "数\n```"))
}

@Test func longRepliesCollapseByRows() {
    #expect(LongReplyCollapse.shouldCollapse(Array(repeating: String(repeating: "a", count: 30), count: LongReplyCollapse.collapseRows + 1).joined(separator: "\n")))
    // \r\n 换行同样计行
    #expect(LongReplyCollapse.shouldCollapse(Array(repeating: String(repeating: "a", count: 30), count: LongReplyCollapse.collapseRows + 1).joined(separator: "\r\n")))
}

@Test func listsWrapButTablesDoNot() {
    // 正文超过 500 个非空白字素、但不足 500 加权字；20 条中英混合内容。
    // 列表每条折成 2 行，表格每条仍是 1 行。
    let item = String(repeating: "长", count: 10) + String(repeating: "a", count: 15)
    let list = Array(repeating: "- " + item, count: 20).joined(separator: "\n")
    let table = (["| 事项 |", "|---|"] + Array(repeating: "| " + item + " |", count: 20)).joined(separator: "\n")
    #expect(LongReplyCollapse.shouldCollapse(list))
    #expect(!LongReplyCollapse.shouldCollapse(table))
}

@Test func blankLinesAndHeadingsAddHeight() {
    // 20 段一行短句：只算正文 20 行不折叠；段间空行和小标题把高度推过一屏
    let lines = Array(repeating: String(repeating: "a", count: 30), count: 20)
    let plain = lines.joined(separator: "\n")
    let spaced = lines.joined(separator: "\n\n")
    let titled = lines.map { "### \($0)" }.joined(separator: "\n")
    #expect(!LongReplyCollapse.shouldCollapse(plain))
    #expect(LongReplyCollapse.shouldCollapse(spaced))
    #expect(LongReplyCollapse.shouldCollapse(titled))
}

// MARK: - 中文（CJK）加权

@Test func cjkWeighsTwiceAsMuchAsASCII() throws {
    // 都放在不折行的代码块里，只比较字数：960 个 ASCII = 480 字，不折叠；960 个汉字折叠
    let ascii = Array(repeating: String(repeating: "a", count: 120), count: 8).joined(separator: "\n")
    let cjk = Array(repeating: String(repeating: "长", count: 120), count: 8).joined(separator: "\n")
    #expect(!LongReplyCollapse.shouldCollapse("```\n" + ascii + "\n```"))
    #expect(LongReplyCollapse.shouldCollapse("```\n" + cjk + "\n```"))
}

@Test func longCJKParagraphCutsByRows() throws {
    let source = String(repeating: "今天天气晴朗适合出门散步。", count: 130)   // 1690 字、无换行
    #expect(LongReplyCollapse.shouldCollapse(source))
    let preview = try #require(LongReplyCollapse.preview(source))
    // 8 行 × 15 字，留 1 字给「…」
    #expect(preview.count == 120)
    #expect(preview.hasSuffix("…"))
    #expect(source.hasPrefix(String(preview.dropLast())))
}

@Test func longASCIIParagraphCutsByCharacters() throws {
    let preview = try #require(LongReplyCollapse.preview(String(repeating: "a", count: 2000)))
    #expect(preview == String(repeating: "a", count: LongReplyCollapse.previewCharacters) + "…")
}

// MARK: - 截断位置

@Test func previewCutsAtLineBoundaryByRowLimit() {
    let lines = numberedLines(60)
    let preview = LongReplyCollapse.preview(lines.joined(separator: "\n"))
    #expect(preview == lines.prefix(LongReplyCollapse.previewRows).joined(separator: "\n"))
}

@Test func previewCutsAtLineBoundaryByCharacterLimit() {
    // 每行 60 个 ASCII（2 行高）：3 行共 180 字、6 行高；第 4 行超出 200 字且已收内容过半，停在行尾
    let line = String(repeating: "a", count: 60)
    let source = Array(repeating: line, count: 20).joined(separator: "\n")
    #expect(LongReplyCollapse.preview(source) == Array(repeating: line, count: 3).joined(separator: "\n"))
}

@Test func previewCutsInsideLineOnlyWhenTooLittleKept() throws {
    let long = String(repeating: "很", count: 2000)
    let preview = try #require(LongReplyCollapse.preview("结论：\n" + long))
    // 「结论：」占 1 行，剩 7 行 × 15 字，留 1 字给「…」
    #expect(preview == "结论：\n" + String(repeating: "很", count: 104) + "…")
}

@Test func previewSkipsLeadingBlankLinesAndHandlesCRLF() {
    let lines = numberedLines(50)
    let preview = LongReplyCollapse.preview("\n  \n" + lines.joined(separator: "\r\n"))
    #expect(preview == lines.prefix(LongReplyCollapse.previewRows).joined(separator: "\n"))
}

@Test func previewDropsTrailingHeadingAndHeaderOnlyTable() {
    // 预算正好停在表头 + 分隔行：没有数据行的表格、它前面的小标题和空行都去掉，只留开头段落
    let intro = String(repeating: "说", count: 60)
    let rows = (1...80).map { "| \($0) | 数据 |" }
    let source = ([intro, "", "### 对比", "", "| 项 | 值 |", "|---|---|"] + rows).joined(separator: "\n")
    #expect(LongReplyCollapse.preview(source) == intro)
}

// MARK: - 代码块

@Test func previewBacksOutOfOpenCodeFence() {
    let code = (1...60).map { "print(\($0))" }
    let source = "示例如下：\n\n```swift\n" + code.joined(separator: "\n") + "\n```\n结束"
    #expect(LongReplyCollapse.preview(source) == "示例如下：")
}

@Test func previewKeepsClosedFenceAndClosesLeadingFence() throws {
    // 已闭合的短代码块完整保留：看：1 行 + 代码块 2 行 + 5 个编号行 = 8 行
    let closed = "看：\n```\nlet a = 1\n```\n" + numberedLines(50).joined(separator: "\n")
    let p1 = try #require(LongReplyCollapse.preview(closed))
    #expect(p1 == "看：\n```\nlet a = 1\n```\n" + numberedLines(5).joined(separator: "\n"))

    // 回复以代码块开头：保留前几行代码并补闭合 ```（开头 ``` 半行 + 7 行代码）
    let code = (1...120).map { "line \($0)" }
    let p2 = try #require(LongReplyCollapse.preview("```python\n" + code.joined(separator: "\n") + "\n```"))
    let rows = p2.components(separatedBy: "\n")
    #expect(rows.first == "```python")
    #expect(rows.last == "```")
    #expect(rows.filter { $0.hasPrefix("```") }.count == 2)
    #expect(MessageMarkdown.blocks(p2) == [.code(language: "python", code: code.prefix(7).joined(separator: "\n"))])
}

// MARK: - 字素（Grapheme）

@Test func previewNeverSplitsGraphemes() throws {
    let family = "👨‍👩‍👧‍👦"
    let accented = "e\u{301}"
    for unit in [family, accented, "🇨🇳"] {
        let source = String(repeating: unit, count: 2000)
        let preview = try #require(LongReplyCollapse.preview(source))
        // 非 ASCII 字素按全宽计：8 行 × 15 个，留 1 个给「…」
        #expect(preview == String(repeating: unit, count: 119) + "…")
        #expect(preview.dropLast().allSatisfy { String($0) == unit })
    }
}

// MARK: - 工具 trace 不铺原文

private let fileText = String(repeating: "文件正文", count: 7500)   // 30000 字

@Test func readFileTraceSummaryOmitsFileText() {
    let first: JSONValue = .object([
        "filename": .string("方案.md"), "offset": .number(0), "text": .string(fileText),
        "next_offset": .number(30000), "has_more": .bool(true),
        "text_chars": .number(52000), "text_status": .string("ready"),
    ])
    #expect(ToolTraceSummary.readFile(first) == "已读取「方案.md」第 1–30000 字，共 52000 字，未读完")

    let whole: JSONValue = .object([
        "filename": .string("notes.txt"), "offset": .number(0), "text": .string("短文件"),
        "next_offset": .null, "has_more": .bool(false), "text_chars": .number(3),
    ])
    #expect(ToolTraceSummary.readFile(whole) == "已读取「notes.txt」全文，共 3 字")
}

@Test func slimmedReadFileTraceFromBackendDecodesAndSummarizes() throws {
    let json = #"{"id":"rf1","name":"read_file","args":{"attachment_id":"att_1"},"result":{"filename":"方案.md","offset":0,"next_offset":30000,"has_more":true,"text_chars":52000,"text_status":"ok","length":30000,"text_omitted":true}}"#
    let trace = try JSONDecoder().decode(ToolTrace.self, from: Data(json.utf8))
    let result = try #require(trace.result)
    #expect(result["text"] == nil)
    #expect(ToolTraceSummary.readFile(result) == "已读取「方案.md」第 1–30000 字，共 52000 字，未读完")
}

@Test func fallbackTraceSummaryIsBounded() {
    let big: JSONValue = .object(["ok": .bool(true), "text": .string(fileText)])
    let summary = ToolTraceSummary.fallback(big)
    #expect(summary.count == ToolTraceSummary.fallbackCharacters + 1)
    #expect(summary.hasPrefix("ok: true; text: 文件正文"))
    #expect(summary.hasSuffix("…"))

    // 短结果与 JSONValue.text 一致
    let small: JSONValue = .object(["ok": .bool(true), "note": .string("原图已附在下一条消息中"),
                                    "ids": .array([.string("a"), .string("b")])])
    #expect(ToolTraceSummary.fallback(small) == small.text)
}

// MARK: - 短回复保护

@Test func shortFormattedReplyIsNotCollapsedByEstimatedRows() {
    // 与误折叠回复同形：若干加粗列表项，不到 500 字但旧规则估算超过 28 行。
    let lines = (1...10).map { "- **项目\($0)**：" + String(repeating: "简要说明", count: 7) }
    let source = lines.joined(separator: "\n\n")
    #expect(source.filter { !$0.isWhitespace }.count < 500)
    #expect(!LongReplyCollapse.shouldCollapse(source))
    #expect(LongReplyCollapse.preview(source) == nil)
}

@Test func shortReplyProtectionIncludesBoundaryAndIgnoresWhitespace() {
    let boundary = String(repeating: "短", count: 500)
    #expect(!LongReplyCollapse.shouldCollapse(boundary))
    #expect(LongReplyCollapse.preview(boundary) == nil)
    #expect(LongReplyCollapse.shouldCollapse(boundary + "长"))
    let padded = Array(repeating: "说明", count: 100).joined(separator: "\n\n\n    ")
    #expect(!LongReplyCollapse.shouldCollapse(padded))
    #expect(LongReplyCollapse.preview(padded) == nil)
}

@Test func shortReplyProtectionCountsWholeGraphemes() {
    for unit in ["👨‍👩‍👧‍👦", "e\u{301}", "🇨🇳"] {
        #expect(!LongReplyCollapse.shouldCollapse(String(repeating: unit, count: 500)))
    }
}
