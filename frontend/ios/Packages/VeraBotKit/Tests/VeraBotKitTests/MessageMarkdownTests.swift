import Foundation
import Testing
@testable import VeraBotCore

// MARK: - 块级解析

@Test func markdownParsesHeadingsParagraphsAndRule() {
    let b = MessageMarkdown.blocks("# 标题\n## 小标题 ##\n第一行\n第二行\n\n第二段\n---\n尾")
    #expect(b == [
        .heading(level: 1, text: "标题"),
        .heading(level: 2, text: "小标题"),
        .paragraph("第一行\n第二行"),
        .paragraph("第二段"),
        .rule,
        .paragraph("尾"),
    ])
    #expect(MessageMarkdown.blocks("#话题") == [.paragraph("#话题")])   // 无空格不是标题
}

@Test func markdownParsesListsWithNesting() {
    let b = MessageMarkdown.blocks("- 苹果\n- **香蕉**\n  - 小香蕉\n1. 第一\n2) 第二\n   续行")
    #expect(b == [
        .list([
            MessageListItem(level: 0, number: nil, text: "苹果"),
            MessageListItem(level: 0, number: nil, text: "**香蕉**"),
            MessageListItem(level: 1, number: nil, text: "小香蕉"),
        ]),
        .list([
            MessageListItem(level: 0, number: 1, text: "第一"),
            MessageListItem(level: 0, number: 2, text: "第二\n续行"),
        ]),
    ])
    // **粗体** 开头、-5°C 不是列表
    #expect(MessageMarkdown.blocks("**结论**：好\n-5°C") == [.paragraph("**结论**：好\n-5°C")])
}

@Test func markdownParsesQuoteAndCode() {
    let b = MessageMarkdown.blocks("> 引用一\n> 引用二\n```swift\nlet a = 1 ~ 2\n\n# 不是标题\n```\n后文")
    #expect(b == [
        .quote("引用一\n引用二"),
        .code(language: "swift", code: "let a = 1 ~ 2\n\n# 不是标题"),
        .paragraph("后文"),
    ])
    // 流式输出中未闭合的代码块
    #expect(MessageMarkdown.blocks("看：\n```\nprint(1)") == [.paragraph("看："), .code(language: nil, code: "print(1)")])
}

@Test func markdownParsesTables() {
    let b = MessageMarkdown.blocks("| 城市 | 温度 |\n| :--- | ---: |\n| 北京 | 15~21°C |\n| 上海 |\n\n完")
    #expect(b == [
        .table(header: ["城市", "温度"], rows: [["北京", "15~21°C"], ["上海", ""]]),
        .paragraph("完"),
    ])
    // 只有竖线、没有分隔行的不是表格
    #expect(MessageMarkdown.blocks("a | b") == [.paragraph("a | b")])
}

// MARK: - 行内格式

@Test func inlineKeepsTildeLiteral() {
    // BUG-01：~ 不能被解析成删除线
    let a = MessageMarkdown.inline("15~21°C 和 ~~不删除~~")
    #expect(String(a.characters) == "15~21°C 和 ~~不删除~~")
    #expect(a.runs.allSatisfy { !($0.inlinePresentationIntent?.contains(.strikethrough) ?? false) })
    // 行内代码里的 ~ 不额外转义
    #expect(String(MessageMarkdown.inline("`a~b`").characters) == "a~b")
}

@Test func inlineParsesEmphasisAndCode() {
    let a = MessageMarkdown.inline("**粗** *斜* `code`")
    #expect(String(a.characters) == "粗 斜 code")
    let intents = a.runs.compactMap(\.inlinePresentationIntent)
    #expect(intents.contains { $0.contains(.stronglyEmphasized) })
    #expect(intents.contains { $0.contains(.emphasized) })
    #expect(intents.contains { $0.contains(.code) })
}

@Test func inlineDetectsLinksPhonesAndEmails() {
    let a = MessageMarkdown.inline("官网 https://example.com/a?b=1 ，邮箱 hi@example.com ，电话 +1 415-555-0100")
    let links = a.runs.compactMap(\.link).map(\.absoluteString)
    #expect(links.contains("https://example.com/a?b=1"))
    #expect(links.contains("mailto:hi@example.com"))
    #expect(links.contains { $0.hasPrefix("tel:") && $0.contains("4155550100") })
}

@Test func inlineKeepsMarkdownLinksAndSkipsCode() {
    let a = MessageMarkdown.inline("[文档](https://docs.example.com) 与 `https://code.example.com`")
    let links = a.runs.compactMap(\.link).map(\.absoluteString)
    #expect(links == ["https://docs.example.com"])
    #expect(String(a.characters) == "文档 与 https://code.example.com")
}

@Test func linksCollectsUniqueURLsAcrossBlocks() {
    let urls = MessageMarkdown.links(in: "- https://a.example.com\n> https://a.example.com\n| x |\n|---|\n| https://b.example.com |\n```\nhttps://c.example.com\n```")
    #expect(urls.map(\.absoluteString) == ["https://a.example.com", "https://b.example.com"])
}

@Test func urlRoutesWebLinksInApp() {
    #expect(URL(string: "https://example.com")!.opensInAppBrowser)
    #expect(URL(string: "HTTP://example.com")!.opensInAppBrowser)
    #expect(!URL(string: "tel:10086")!.opensInAppBrowser)
    #expect(!URL(string: "mailto:a@b.com")!.opensInAppBrowser)
}
