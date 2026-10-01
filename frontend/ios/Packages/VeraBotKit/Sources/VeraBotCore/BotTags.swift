// Bot 标签规则，与后端 `clean_tags` 一致：trim、丢掉空白和重复、最多 5 个、每个最多 12 个字、拒绝控制字符。
import Foundation

public struct TagNormalization: Equatable, Sendable {
    public let tags: [String]
    /// 非 nil 时列表不可提交，文案可直接展示。
    public let error: String?
}

public enum BotTagRules {
    public static let maxCount = 5
    public static let maxLength = 12

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
                return TagNormalization(tags: [], error: "每个标签最多 12 个字")
            }
            if seen.contains(tag) { continue }
            seen.insert(tag)
            out.append(tag)
        }
        if out.count > maxCount {
            return TagNormalization(tags: [], error: "每个 Bot 最多 5 个标签")
        }
        return TagNormalization(tags: out, error: nil)
    }
}
