import Foundation

/// 来源来自实际工具结果；模型生成的链接不会成为来源卡片。
public struct WebSource: Identifiable, Sendable, Hashable {
    public let queryID: String
    public let resultID: String
    public let title: String
    public let url: URL
    public let publisher: String
    public let publishedAt: String?
    public let queriedAt: String?
    public let fetchedAt: String?
    public let cacheHit: Bool
    public let citationNumber: Int?

    public var id: String { queryID + ":" + resultID }

    public static func sources(from traces: [ToolTrace]) -> [WebSource] {
        var result: [WebSource] = []
        var indices: [String: Int] = [:]
        for trace in traces where trace.name == "web_search" || trace.name == "web_read_result" {
            guard trace.result?["error"] == nil else { continue }
            for row in trace.result?["sources"]?.arrayValue ?? [] {
                guard let queryID = string(row["query_id"]), let resultID = string(row["result_id"]),
                      let rawURL = string(row["url"]), let url = safeURL(rawURL) else { continue }
                let source = WebSource(queryID: queryID, resultID: resultID,
                                       title: String((string(row["title"]) ?? url.host ?? "来源").prefix(200)), url: url,
                                       publisher: string(row["publisher"]) ?? url.host ?? "",
                                       publishedAt: string(row["published_at"]), queriedAt: string(row["queried_at"]),
                                       fetchedAt: string(row["fetched_at"]), cacheHit: row["cache_hit"] == .bool(true),
                                       citationNumber: Int(row["citation_number"]?.text ?? ""))
                if let index = indices[source.id] {
                    result[index] = source
                } else {
                    indices[source.id] = result.count
                    result.append(source)
                }
            }
        }
        return result
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case .string(let text) = value, !text.isEmpty else { return nil }
        return text
    }

    private static func safeURL(_ raw: String) -> URL? {
        guard raw.count <= 2048, !raw.contains("\\"),
              raw.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let parts = URLComponents(string: raw), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
              let host = parts.host?.lowercased(), host.contains("."), !host.contains(":"), !host.contains("%"),
              host != "localhost", ![".localhost", ".local", ".internal", ".lan", ".home", ".test", ".invalid"].contains(where: host.hasSuffix),
              !host.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return parts.url
    }
}
