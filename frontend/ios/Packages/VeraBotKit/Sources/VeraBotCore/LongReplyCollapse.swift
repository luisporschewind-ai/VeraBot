import Foundation

// MARK: - 长回复折叠（Long Reply Collapse）
//
// 纯 Foundation、无 UI：私聊里超长的 Bot 回复默认收起，气泡只排版截断后的预览，
// 展开后才交给 MessageContentView 渲染全文 Markdown。规格见 docs/specs/long-reply-collapse.md。
//
// 「长」按手机上的排版高度估算，不按原文字数或换行数：
// - 宽度按半宽单位计：ASCII 占 1，中文 / 全角标点 / emoji 等其他字素占 2。气泡正文宽约 267pt、17pt 字号，
//   一行约 15 个中文字 = 30 个半宽单位（`rowWidth`）。
// - 高度按「半行」计（正文一行 = 2）：段落 / 列表 / 引用按宽度折行；标题额外 +1；
//   表格行、代码行横向滚动不折行，每行 2；表格分隔行、``` 边框、空行各 1。
// 判定与截断都有提前退出，耗时只与阈值有关、与全文长度无关（每行至少 1 个半行、每个字素至少 1 个半宽单位）。

public enum LongReplyCollapse {
    /// 加权字数（中文 1、ASCII 0.5）超过 500 即折叠。正文段落通常先触发行数阈值；
    /// 这条主要兜住不折行的宽表格 / 长代码，它们行数少但信息量大。
    public static let collapseCharacters = 500
    /// 估算排版行数超过 28 即折叠：6.1 英寸 iPhone 对话可视区约 660pt、中文正文一行约 23pt，约一屏。
    public static let collapseRows = 28
    /// 预览上限：≤ 200 个字素，且估算 ≤ 8 行（约 1/3 屏）；与折叠阈值保持 3 倍以上差距，「展开」才有实质内容。
    public static let previewCharacters = 200
    public static let previewRows = 8

    /// 一行正文的宽度（半宽单位）
    static let rowWidth = 30

    public static func shouldCollapse(_ text: String) -> Bool {
        var width = 0
        var halfRows = 0
        var lineWidth = 0
        var inFence = false
        var lineStart = text.startIndex
        var index = text.startIndex
        while true {
            let atEnd = index == text.endIndex
            if atEnd || isLineBreak(text[index]) {
                let trimmed = text[lineStart..<index].trimmingCharacters(in: .whitespaces)
                halfRows += halfRowCost(trimmed, width: lineWidth, inFence: inFence)
                if trimmed.hasPrefix("```") { inFence.toggle() }
                if halfRows > collapseRows * 2 { return true }
                if atEnd { return false }
                index = text.index(after: index)
                lineStart = index
                lineWidth = 0
                continue
            }
            let w = weight(text[index])
            lineWidth += w
            width += w
            if width > collapseCharacters * 2 { return true }
            index = text.index(after: index)
        }
    }

    /// 收起时显示的预览；不需要折叠时返回 nil。
    ///
    /// - 跳过开头空行，逐行收入，字数或估算行数到上限时停在最后一整行（行尾截断）。
    /// - 整行放不下、且已收内容不足两项上限的一半时，才在行内按字素截断并补「…」（截断后连同「…」不超过剩余行数）。
    /// - 截断点落在 ``` 代码块内：代码块前有正文则退回到代码块之前；没有则保留已收代码行并补闭合 ```，
    ///   保证预览本身是完整的 Markdown，不会出现半个代码块。
    /// - 去掉末尾空行、末尾标题，以及只剩表头（没有数据行）的表格；至少保留第一行。
    public static func preview(_ text: String) -> String? {
        guard shouldCollapse(text) else { return nil }
        let rowBudget = previewRows * 2
        var lines: [String] = []
        var usedCharacters = 0
        var usedRows = 0
        var fenceStart: Int?   // 未闭合 ``` 在 lines 中的下标
        var start = text.startIndex

        while start < text.endIndex {
            let budget = previewCharacters - usedCharacters
            var end = start
            var count = 0
            var width = 0
            while end < text.endIndex, !isLineBreak(text[end]), count <= budget {
                width += weight(text[end])
                end = text.index(after: end)
                count += 1
            }
            if count <= budget {
                let line = text[start..<end]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let next = end < text.endIndex ? text.index(after: end) : end
                if lines.isEmpty && trimmed.isEmpty {
                    start = next
                    continue
                }
                let cost = halfRowCost(trimmed, width: width, inFence: fenceStart != nil)
                if usedRows + cost <= rowBudget {
                    lines.append(String(line))
                    usedCharacters += count
                    usedRows += cost
                    if trimmed.hasPrefix("```") { fenceStart = fenceStart == nil ? lines.count - 1 : nil }
                    start = next
                    continue
                }
            }
            if usedCharacters < previewCharacters / 2 && usedRows < rowBudget / 2 {
                let maxWidth = (rowBudget - usedRows) / 2 * rowWidth - weight("…")
                let cut = prefix(of: text[start...], maxCharacters: budget, maxWidth: maxWidth)
                if !cut.isEmpty { lines.append(cut + "…") }
            }
            break
        }

        if let fenceStart {
            if lines[..<fenceStart].contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                lines.removeSubrange(fenceStart...)
            } else {
                lines.append("```")
            }
        }
        while lines.count > 1 {
            let last = lines[lines.count - 1].trimmingCharacters(in: .whitespaces)
            if last.isEmpty || MessageMarkdown.heading(last) != nil {
                lines.removeLast()
                continue
            }
            let tableRun = lines.reversed().prefix(while: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }).count
            if tableRun < lines.count, tableRun == 1 || (tableRun == 2 && MessageMarkdown.isTableSeparator(last)) {
                lines.removeLast(tableRun)
                continue
            }
            break
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// 一行源文本排版后约占的高度，单位半行（正文一行 = 2）。`trimmed` 已去掉首尾空格。
    static func halfRowCost(_ trimmed: String, width: Int, inFence: Bool) -> Int {
        if trimmed.hasPrefix("```") { return 1 }
        if inFence { return 2 }
        if trimmed.isEmpty { return 1 }
        if trimmed.hasPrefix("|") { return MessageMarkdown.isTableSeparator(trimmed) ? 1 : 2 }
        let rows = 2 * max(1, (width + rowWidth - 1) / rowWidth)
        return MessageMarkdown.heading(trimmed) != nil ? rows + 1 : rows
    }

    /// 本行开头不超过 maxCharacters 个字素、总宽不超过 maxWidth 的部分。
    static func prefix(of text: Substring, maxCharacters: Int, maxWidth: Int) -> String {
        var end = text.startIndex
        var count = 0
        var width = 0
        while end < text.endIndex, !isLineBreak(text[end]), count < maxCharacters {
            let w = weight(text[end])
            if width + w > maxWidth { break }
            width += w
            count += 1
            end = text.index(after: end)
        }
        return String(text[..<end])
    }

    static func weight(_ c: Character) -> Int { c.isASCII ? 1 : 2 }

    static func isLineBreak(_ c: Character) -> Bool { c == "\n" || c == "\r\n" }
}
