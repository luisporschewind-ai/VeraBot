import Foundation
import VeraBotCore

private struct FeedCatalogResponse: Decodable, Sendable { let sources: [FeedCatalogSource] }
private struct FeedSourcesResponse: Decodable, Sendable { let sources: [FeedSource] }
private struct FeedRefreshResponse: Decodable, Sendable { let queued: Bool }
private struct FeedSuggestRequest: Encodable {
    let bot_ids: [Int]
    let topics: [String]
    let use_memory: Bool
}
private struct FeedSourceState: Encodable { let enabled: Bool }

extension APIClient: FeedAPI {
    public func feedPlan() async throws -> FeedPlan { try await call("/api/feed/plan") }
    public func feedSavePlan(_ plan: FeedPlanUpdate) async throws -> FeedPlan {
        try await call("/api/feed/plan", method: "PUT", body: encode(plan))
    }
    public func feedSuggest(botIDs: [Int], topics: [String], useMemory: Bool) async throws -> FeedSuggestion {
        try await call("/api/feed/plan/suggest", method: "POST", body: encode(FeedSuggestRequest(bot_ids: botIDs, topics: topics, use_memory: useMemory)))
    }
    public func feedCatalog() async throws -> [FeedCatalogSource] {
        let response: FeedCatalogResponse = try await call("/api/feed/catalog")
        return response.sources
    }
    public func feedSources() async throws -> [FeedSource] {
        let response: FeedSourcesResponse = try await call("/api/feed/sources")
        return response.sources
    }
    public func feedAddSource(_ source: FeedSourceCreate) async throws -> FeedSource {
        try await call("/api/feed/sources", method: "POST", body: encode(source))
    }
    public func feedSetSource(id: Int, enabled: Bool) async throws -> FeedSource {
        try await call("/api/feed/sources/\(id)", method: "PATCH", body: encode(FeedSourceState(enabled: enabled)))
    }
    public func feedRefresh() async throws -> Bool {
        let response: FeedRefreshResponse = try await call("/api/feed/refresh", method: "POST")
        return response.queued
    }
    public func feedItems(query: FeedQuery, cursor: String?) async throws -> FeedPage {
        var params = [URLQueryItem(name: "limit", value: "20"), .init(name: "saved_only", value: query.savedOnly ? "true" : "false")]
        if let cursor, !cursor.isEmpty { params.append(.init(name: "cursor", value: cursor)) }
        if let kind = query.kind, !kind.isEmpty { params.append(.init(name: "kind", value: kind)) }
        if let botID = query.botID { params.append(.init(name: "bot_id", value: String(botID))) }
        return try await call("/api/feed/items", query: params)
    }
    public func feedItem(id: Int) async throws -> FeedItem { try await call("/api/feed/items/\(id)") }
    public func feedSetState(id: Int, state: FeedItemState) async throws -> FeedItem {
        try await call("/api/feed/items/\(id)/state", method: "PATCH", body: encode(state))
    }
    public func feedContext(id: Int, botID: Int) async throws -> FeedContext {
        try await call("/api/feed/items/\(id)/context", query: [.init(name: "bot_id", value: String(botID))])
    }
}
