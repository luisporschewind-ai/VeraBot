import Foundation
import VeraBotCore

/// Feed stays separate from the chat protocol so existing chat consumers and mocks remain stable.
public protocol FeedAPI: Sendable {
    func feedPlan() async throws -> FeedPlan
    func feedSavePlan(_ plan: FeedPlanUpdate) async throws -> FeedPlan
    func feedSuggest(botIDs: [Int], topics: [String], useMemory: Bool) async throws -> FeedSuggestion
    func feedCatalog() async throws -> [FeedCatalogSource]
    func feedSources() async throws -> [FeedSource]
    func feedAddSource(_ source: FeedSourceCreate) async throws -> FeedSource
    func feedSetSource(id: Int, enabled: Bool) async throws -> FeedSource
    func feedRefresh() async throws -> Bool
    func feedItems(query: FeedQuery, cursor: String?) async throws -> FeedPage
    func feedItem(id: Int) async throws -> FeedItem
    func feedSetState(id: Int, state: FeedItemState) async throws -> FeedItem
    func feedContext(id: Int, botID: Int) async throws -> FeedContext
}

public extension FeedAPI {
    func feedSavePlan(_ plan: FeedPlanUpdate) async throws -> FeedPlan { throw URLError(.unsupportedURL) }
    func feedSuggest(botIDs: [Int], topics: [String], useMemory: Bool) async throws -> FeedSuggestion { throw URLError(.unsupportedURL) }
    func feedAddSource(_ source: FeedSourceCreate) async throws -> FeedSource { throw URLError(.unsupportedURL) }
    func feedSetSource(id: Int, enabled: Bool) async throws -> FeedSource { throw URLError(.unsupportedURL) }
    func feedRefresh() async throws -> Bool { throw URLError(.unsupportedURL) }
    func feedItem(id: Int) async throws -> FeedItem { throw URLError(.unsupportedURL) }
    func feedContext(id: Int, botID: Int) async throws -> FeedContext { throw URLError(.unsupportedURL) }
}
