import Foundation

// MARK: - 消息富文本（Message Markdown）
//
// 纯 Foundation、无 UI：把 Bot 回复拆成块（标题 / 段落 / 列表 / 引用 / 代码块 / 表格 / 分隔线），
// 块内行内格式（粗体 / 斜体 / 行内代码 / [链接](url)）交给 Foundation 的 AttributedString(markdown:)，
// 再用 NSDataDetector 自动识别网址、电话、邮箱并加上 .link。App 里的 MessageContentView 只负责排版。
//
// 约定：
// - BUG-01：「15~21°C」里的 ~ 不能变成删除线：行内代码以外的 ~ 一律转义后按原文显示。
// - 段落内保留单个换行（聊天回复常用单换行分行），空行分段。
// - 流式输出中未闭合的 ``` 代码块按代码块显示到末尾。

public struct MessageListItem: Equatable, Sendable {
    /// 缩进层级（0 起，每 2 个空格 / 1 个 tab 一级）
    public var level: Int
    /// 有序列表的序号；无序列表为 nil
    public var number: Int?
    public var text: String

    public init(level: Int, number: Int?, text: String) {
        self.level = level
        self.number = number
        self.text = text
    }
}

public enum MessageBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([MessageListItem])
    case quote(String)
    case code(language: String?, code: String)
    case table(header: [String], rows: [[String]])
    case rule
}

public enum MessageMarkdown {
    // MARK: 块级解析

    public static func blocks(_ source: String) -> [MessageBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MessageBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var items: [MessageListItem] = []
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
        }
        func flushList() {
            if !items.isEmpty { blocks.append(.list(items)); items = [] }
        }
        func flushAll() { flushParagraph(); flushQuote(); flushList() }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // ``` 代码块
            if trimmed.hasPrefix("```") {
                flushAll()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(language: lang.isEmpty ? nil : lang, code: code.joined(separator: "\n")))
                i += 1   // 跳过闭合 ```（未闭合时已到末尾）
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                i += 1
                continue
            }

            // 表格：表头行 + 分隔行（| --- | :-: |）
            if line.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushAll()
                let header = cells(line)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].contains("|"),
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    var row = cells(lines[i])
                    if row.count < header.count { row += Array(repeating: "", count: header.count - row.count) }
                    rows.append(Array(row.prefix(max(header.count, 1))))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            if let (level, text) = heading(trimmed) {
                flushAll()
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph(); flushList()
                var body = String(trimmed.dropFirst())
                if body.hasPrefix(" ") { body.removeFirst() }
                quote.append(body)
                i += 1
                continue
            }

            if let item = listItem(line) {
                flushParagraph(); flushQuote()
                // 顶层的有序 / 无序切换时另起一个列表
                if item.level == 0, let last = items.last(where: { $0.level == 0 }),
                   (last.number == nil) != (item.number == nil) {
                    flushList()
                }
                items.append(item)
                i += 1
                continue
            }

            // 列表项的缩进续行
            if !items.isEmpty, line.first == " " || line.first == "\t" {
                items[items.count - 1].text += "\n" + trimmed
                i += 1
                continue
            }

            flushQuote(); flushList()
            paragraph.append(line)
            i += 1
        }
        flushAll()
        return blocks
    }

    static func heading(_ trimmed: String) -> (Int, String)? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        return (hashes, rest.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let c = compact.first, "-*_".contains(c) else { return false }
        return compact.allSatisfy { $0 == c }
    }

    static func listItem(_ line: String) -> MessageListItem? {
        var indent = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == " " || line[idx] == "\t" {
            indent += line[idx] == "\t" ? 2 : 1
            idx = line.index(after: idx)
        }
        let rest = line[idx...]
        let level = min(indent / 2, 3)
        // 无序：- * + •
        if let c = rest.first, "-*+•".contains(c) {
            let after = rest.dropFirst()
            if after.first == " " {
                return MessageListItem(level: level, number: nil, text: after.trimmingCharacters(in: .whitespaces))
            }
            return nil
        }
        // 有序：1. / 1)
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 4, let n = Int(digits) else { return nil }
        let after = rest.dropFirst(digits.count)
        guard let mark = after.first, mark == "." || mark == ")", after.dropFirst().first == " " else { return nil }
        return MessageListItem(level: level, number: n, text: after.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") || t.hasPrefix(":") || t.hasPrefix("-") else { return false }
        let parts = cells(t)
        return !parts.isEmpty && parts.allSatisfy { p in
            let core = p.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return core.count >= 1 && core.allSatisfy { $0 == "-" }
        }
    }

    static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        // 支持 \| 转义
        let placeholder = "\u{0}"
        return t.replacingOccurrences(of: "\\|", with: placeholder)
            .components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: placeholder, with: "|").trimmingCharacters(in: .whitespaces) }
    }

    // MARK: 行内格式 + 自动链接

    /// 行内 Markdown（粗体 / 斜体 / 行内代码 / [文字](url)）+ 自动识别网址、电话、邮箱。
    public static func inline(_ s: String, detectLinks: Bool = true) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var attr = (try? AttributedString(markdown: escapeTildes(s), options: opts)) ?? AttributedString(s)
        if detectLinks { addDetectedLinks(to: &attr) }
        return attr
    }

    /// 行内代码以外的 ~ 转义（BUG-01：避免 15~21°C 变成删除线）
    static func escapeTildes(_ s: String) -> String {
        guard s.contains("~") else { return s }
        var out = ""
        var inCode = false
        for ch in s {
            if ch == "`" { inCode.toggle() }
            if ch == "~" && !inCode { out += "\\~" } else { out.append(ch) }
        }
        return out
    }

    nonisolated(unsafe) private static let detector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue)

    static func addDetectedLinks(to attr: inout AttributedString) {
        guard let detector else { return }
        let plain = String(attr.characters)
        guard !plain.isEmpty else { return }
        let matches = detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain))
        for m in matches {
            guard let r = Range(m.range, in: plain), let url = url(for: m) else { continue }
            let lower = attr.characters.index(attr.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: r.lowerBound))
            let upper = attr.characters.index(lower, offsetBy: plain.distance(from: r.lowerBound, to: r.upperBound))
            let range = lower..<upper
            // 已是 Markdown 链接或在行内代码里的不再处理
            let skip = attr[range].runs.contains { run in
                run.link != nil || (run.inlinePresentationIntent?.contains(.code) ?? false)
            }
            if !skip { attr[range].link = url }
        }
    }

    static func url(for m: NSTextCheckingResult) -> URL? {
        if m.resultType == .phoneNumber, let number = m.phoneNumber {
            let digits = number.filter { $0.isNumber || $0 == "+" }
            return digits.count >= 5 ? URL(string: "tel:\(digits)") : nil
        }
        return m.url
    }

    /// 文本里所有可点链接（Markdown 链接 + 自动识别），按出现顺序去重。用于长按「复制链接」。
    public static func links(in source: String) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for text in blocks(source).flatMap(inlineTexts) {
            for run in inline(text).runs {
                if let url = run.link, seen.insert(url.absoluteString).inserted { result.append(url) }
            }
        }
        return result
    }

    static func inlineTexts(_ block: MessageBlock) -> [String] {
        switch block {
        case .heading(_, let t), .paragraph(let t), .quote(let t): [t]
        case .list(let items): items.map(\.text)
        case .table(let header, let rows): header + rows.flatMap { $0 }
        case .code, .rule: []
        }
    }
}

public extension URL {
    /// http / https：App 内用 SFSafariViewController 打开；其他（tel: / mailto: 等）交给系统
    var opensInAppBrowser: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
