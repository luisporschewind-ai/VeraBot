import Foundation

// MARK: - 长回复折叠（Long Reply Collapse）
//
// 纯 Foundation、无 UI：私聊里超长的 Bot 回复默认收起，气泡只排版截断后的预览，
// 展开后才交给 MessageContentView 渲染全文 Markdown。规格见 docs/specs/long-reply-collapse.md。
//
// 字数一律按字素（Character）计，中文、emoji、组合字符都算 1 个；行按 "\n" / "\r\n" 分。
// 判定与截断都有提前退出，耗时只与阈值有关、与全文长度无关（行数统计按 UTF-8 字节扫描换行）。

public enum LongReplyCollapse {
    /// 超过任一阈值即折叠：约 3～4 屏中文气泡，或长列表 / 长代码这类行数多的回复。
    public static let collapseCharacters = 1500
    public static let collapseLines = 40
    /// 预览上限：约半屏中文气泡；与折叠阈值保持数倍差距，避免「展开」只多出几行。
    public static let previewCharacters = 300
    public static let previewLines = 10

    public static func shouldCollapse(_ text: String) -> Bool {
        if hasMoreLines(text, than: collapseLines) { return true }
        // UTF-8 字节数 ≥ 字符数：字节数不超阈值时不必逐字计数
        guard text.utf8.count > collapseCharacters else { return false }
        guard let index = text.index(text.startIndex, offsetBy: collapseCharacters, limitedBy: text.endIndex) else { return false }
        return index < text.endIndex
    }

    /// 收起时显示的预览；不需要折叠时返回 nil。
    ///
    /// - 跳过开头空行，逐行收入，行数或字数到上限时停在最后一整行（行尾截断）。
    /// - 整行放不下、且已收内容不足字数上限一半时，才在行内按字素截断并补「…」。
    /// - 截断点落在 ``` 代码块内：代码块前有正文则退回到代码块之前；没有则保留已收代码行并补闭合 ```，
    ///   保证预览本身是完整的 Markdown，不会出现半个代码块。
    public static func preview(_ text: String) -> String? {
        guard shouldCollapse(text) else { return nil }
        var lines: [String] = []
        var used = 0
        var fenceStart: Int?   // 未闭合 ``` 在 lines 中的下标
        var start = text.startIndex

        while lines.count < previewLines, start < text.endIndex {
            let budget = previewCharacters - used
            var end = start
            var count = 0
            while end < text.endIndex, !isLineBreak(text[end]), count <= budget {
                end = text.index(after: end)
                count += 1
            }
            if count > budget {
                if used < previewCharacters / 2 {
                    lines.append(String(text[start..<text.index(start, offsetBy: budget)]) + "…")
                }
                break
            }
            let line = text[start..<end]
            start = end < text.endIndex ? text.index(after: end) : end
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if lines.isEmpty && trimmed.isEmpty { continue }
            lines.append(String(line))
            used += count
            if trimmed.hasPrefix("```") { fenceStart = fenceStart == nil ? lines.count - 1 : nil }
        }

        if let fenceStart {
            if lines[..<fenceStart].contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                lines.removeSubrange(fenceStart...)
            } else {
                lines.append("```")
            }
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func hasMoreLines(_ text: String, than limit: Int) -> Bool {
        var newlines = 0
        for byte in text.utf8 where byte == 0x0A {
            newlines += 1
            if newlines >= limit { return true }
        }
        return false
    }

    static func isLineBreak(_ c: Character) -> Bool { c == "\n" || c == "\r\n" }
}
