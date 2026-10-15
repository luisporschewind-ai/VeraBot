import Foundation

/// 对话里工具 trace 卡片的一句话说明。工具结果可能带原文（read_file 一次最多 3 万字文件内容），
/// 卡片只显示说明或截断后的开头，不把原文铺进对话行。
public enum ToolTraceSummary {
    /// 未专门处理的工具：说明最多这么多字素，超出补「…」。
    public static let fallbackCharacters = 160

    /// read_file：「已读取「a.txt」第 1–30000 字，共 52000 字，未读完」；不含文件内容。
    public static func readFile(_ result: JSONValue) -> String {
        let name = result["filename"]?.text ?? ""
        let file = name.isEmpty ? "文件" : "「\(name)」"
        let offset = Int(result["offset"]?.text ?? "") ?? 0
        let total = Int(result["text_chars"]?.text ?? "") ?? 0
        let hasMore = result["has_more"] == .bool(true)
        let end = hasMore ? Int(result["next_offset"]?.text ?? "") ?? 0 : total
        guard total > 0 else { return "已读取\(file)" }
        if offset == 0 && !hasMore { return "已读取\(file)全文，共 \(total) 字" }
        guard end > offset else { return "已读取\(file)，共 \(total) 字" }
        return "已读取\(file)第 \(offset + 1)–\(end) 字，共 \(total) 字" + (hasMore ? "，未读完" : "")
    }

    /// 与 `JSONValue.text` 同格式（键排序后 `key: value`，以「; 」/「, 」连接），
    /// 但写满 `limit` 个字素即停，长字符串只取开头，不会先拼出整段原文。
    public static func fallback(_ result: JSONValue, limit: Int = fallbackCharacters) -> String {
        var out = ""
        var remaining = limit
        write(result, into: &out, remaining: &remaining)
        return remaining < 0 ? out + "…" : out
    }

    private static func write(_ value: JSONValue, into out: inout String, remaining: inout Int) {
        switch value {
        case .object(let object):
            for (i, key) in object.keys.sorted().enumerated() {
                if i > 0 { put("; ", into: &out, remaining: &remaining) }
                put("\(key): ", into: &out, remaining: &remaining)
                if let child = object[key] { write(child, into: &out, remaining: &remaining) }
                if remaining < 0 { return }
            }
        case .array(let array):
            for (i, child) in array.enumerated() {
                if i > 0 { put(", ", into: &out, remaining: &remaining) }
                write(child, into: &out, remaining: &remaining)
                if remaining < 0 { return }
            }
        default:
            put(value.text, into: &out, remaining: &remaining)
        }
    }

    /// remaining < 0 表示已截断
    private static func put(_ s: String, into out: inout String, remaining: inout Int) {
        guard remaining >= 0 else { return }
        let piece = s.prefix(remaining + 1)
        if piece.count > remaining {
            out += piece.prefix(remaining)
            remaining = -1
        } else {
            out += piece
            remaining -= piece.count
        }
    }
}
