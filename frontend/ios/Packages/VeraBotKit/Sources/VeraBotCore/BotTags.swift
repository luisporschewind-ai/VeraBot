// Bot 标签规则，与后端 `core/tags.py` + `clean_tags` 一致：trim、丢掉空白和重复、最多 3 个、每个最多 4 个字（按 Unicode 码点）、拒绝控制字符。
// 上限与错误文案由后端 TAG-10 契约测试读取本文件断言。
import Foundation

public struct TagNormalization: Equatable, Sendable {
    public let tags: [String]
    /// 非 nil 时列表不可提交，文案可直接展示。
    public let error: String?
}

public enum BotTagRules {
    public static let maxCount = 3
    public static let maxLength = 4
    /// 编辑框的分隔符：英文 / 中文逗号、顿号、空白（含全角空格）。
    static let separators = CharacterSet(charactersIn: ",，、").union(.whitespacesAndNewlines)

    /// 成功时 `error == nil`，`tags` 为清洗后的列表（保留首次出现的顺序）。
    public static func normalized(_ raw: [String]) -> TagNormalization {
        var out: [String] = []
        var seen = Set<String>()
        for item in raw {
            let tag = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if tag.isEmpty { continue }
            if tag.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                return TagNormalization(tags: [], error: "标签不能包含控制字符")
            }
            if tag.unicodeScalars.count > maxLength {
                return TagNormalization(tags: [], error: "每个标签最多 \(maxLength) 个字")
            }
            if seen.contains(tag) { continue }
            seen.insert(tag)
            out.append(tag)
        }
        if out.count > maxCount {
            return TagNormalization(tags: [], error: "每个 Bot 最多 \(maxCount) 个标签")
        }
        return TagNormalization(tags: out, error: nil)
    }

    /// 解析编辑框里的一行文字（「搜索, 查询、调研」）：按分隔符拆开后走 `normalized`。
    public static func parse(_ text: String) -> TagNormalization {
        normalized(text.components(separatedBy: separators))
    }

    /// 展示用：「搜索, 查询, 调研」。编辑框初始值也用它。
    public static func display(_ tags: [String]) -> String {
        tags.joined(separator: ", ")
    }
}
