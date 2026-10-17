import Foundation

// Feed timestamps remain server ISO-8601 strings; optional values retain null semantics.
public struct FeedPlan: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var botIDs: [Int]
    public var topics: [String]
    public var excludedTopics: [String]
    public var useMemory: Bool
    public var dailyLimit: Int
    public var version: Int

    public init(enabled: Bool = false, botIDs: [Int] = [], topics: [String] = [], excludedTopics: [String] = [], useMemory: Bool = true, dailyLimit: Int = 20, version: Int = 0) {
        self.enabled = enabled
        self.botIDs = botIDs
        self.topics = topics
        self.excludedTopics = excludedTopics
        self.useMemory = useMemory
        self.dailyLimit = dailyLimit
        self.version = version
    }
    enum CodingKeys: String, CodingKey {
        case enabled
        case botIDs = "bot_ids"
        case topics
        case excludedTopics = "excluded_topics"
        case useMemory = "use_memory"
        case dailyLimit = "daily_limit"
        case version
    }
}

public struct FeedPlanUpdate: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var botIDs: [Int]
    public var topics: [String]
    public var excludedTopics: [String]
    public var useMemory: Bool
    public var expectedVersion: Int

    public init(enabled: Bool, botIDs: [Int], topics: [String], excludedTopics: [String], useMemory: Bool, expectedVersion: Int) {
        self.enabled = enabled
        self.botIDs = botIDs
        self.topics = topics
        self.excludedTopics = excludedTopics
        self.useMemory = useMemory
        self.expectedVersion = expectedVersion
    }
    enum CodingKeys: String, CodingKey {
        case enabled
        case botIDs = "bot_ids"
        case topics
        case excludedTopics = "excluded_topics"
        case useMemory = "use_memory"
        case expectedVersion = "expected_version"
    }
}

public struct FeedCatalogSource: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var url: String
    public var kind: String
    public var topics: [String]
    public var description: String
    public var reason: String

    public init(id: String, name: String, url: String, kind: String = "news", topics: [String] = [], description: String = "", reason: String = "") {
        self.id = id
        self.name = name
        self.url = url
        self.kind = kind
        self.topics = topics
        self.description = description
        self.reason = reason
    }
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case kind
        case topics
        case description
        case reason
    }
}

public struct FeedSource: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var url: String
    public var kind: String
    public var botID: Int?
    public var enabled: Bool
    public var lastSuccessAt: String?
    public var nextFetchAt: String?
    public var lastError: String?
    public var failureCount: Int

    public init(id: Int, name: String = "", url: String = "", kind: String = "news", botID: Int? = nil, enabled: Bool = true, lastSuccessAt: String? = nil, nextFetchAt: String? = nil, lastError: String? = nil, failureCount: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.kind = kind
        self.botID = botID
        self.enabled = enabled
        self.lastSuccessAt = lastSuccessAt
        self.nextFetchAt = nextFetchAt
        self.lastError = lastError
        self.failureCount = failureCount
    }
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case kind
        case botID = "bot_id"
        case enabled
        case lastSuccessAt = "last_success_at"
        case nextFetchAt = "next_fetch_at"
        case lastError = "last_error"
        case failureCount = "failure_count"
    }
}

public struct FeedSourceCreate: Codable, Sendable, Hashable {
    public var name: String
    public var url: String
    public var kind: String
    public var botID: Int?

    public init(name: String, url: String, kind: String, botID: Int? = nil) {
        self.name = name
        self.url = url
        self.kind = kind
        self.botID = botID
    }
    enum CodingKeys: String, CodingKey {
        case name
        case url
        case kind
        case botID = "bot_id"
    }
}

public struct FeedRecommendation: Codable, Sendable, Hashable {
    public var botID: Int
    public var botName: String
    public var reason: String

    public init(botID: Int, botName: String, reason: String) {
        self.botID = botID
        self.botName = botName
        self.reason = reason
    }
    enum CodingKeys: String, CodingKey {
        case botID = "bot_id"
        case botName = "bot_name"
        case reason
    }
}

public struct FeedItem: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var kind: String
    public var title: String
    public var url: String
    public var author: String?
    public var sourceID: Int
    public var sourceName: String
    public var botID: Int?
    public var botName: String?
    public var publishedAt: String?
    public var createdAt: String
    public var summary: String
    public var summaryBasis: String
    public var recommendationReason: String
    public var imageURL: String?
    public var mediaURL: String?
    public var durationSeconds: Int?
    public var read: Bool
    public var saved: Bool
    public var dismissed: Bool
    public var recommendedBy: [FeedRecommendation]

    public init(id: Int, kind: String = "news", title: String = "", url: String = "", author: String? = nil, sourceID: Int = 0, sourceName: String = "", botID: Int? = nil, botName: String? = nil, publishedAt: String? = nil, createdAt: String = "", summary: String = "", summaryBasis: String = "description", recommendationReason: String = "", imageURL: String? = nil, mediaURL: String? = nil, durationSeconds: Int? = nil, read: Bool = false, saved: Bool = false, dismissed: Bool = false, recommendedBy: [FeedRecommendation] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.url = url
        self.author = author
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.botID = botID
        self.botName = botName
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.summary = summary
        self.summaryBasis = summaryBasis
        self.recommendationReason = recommendationReason
        self.imageURL = imageURL
        self.mediaURL = mediaURL
        self.durationSeconds = durationSeconds
        self.read = read
        self.saved = saved
        self.dismissed = dismissed
        self.recommendedBy = recommendedBy
    }
    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case url
        case author
        case sourceID = "source_id"
        case sourceName = "source_name"
        case botID = "bot_id"
        case botName = "bot_name"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case summary
        case summaryBasis = "summary_basis"
        case recommendationReason = "recommendation_reason"
        case imageURL = "image_url"
        case mediaURL = "media_url"
        case durationSeconds = "duration_seconds"
        case read
        case saved
        case dismissed
        case recommendedBy = "recommended_by"
    }
}

public struct FeedPage: Codable, Sendable, Hashable {
    public var items: [FeedItem]
    public var nextCursor: String?

    public init(items: [FeedItem], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

public struct FeedSuggestion: Codable, Sendable, Hashable {
    public var topics: [String]
    public var sources: [FeedCatalogSource]
    public var basis: String

    public init(topics: [String] = [], sources: [FeedCatalogSource] = [], basis: String = "") {
        self.topics = topics
        self.sources = sources
        self.basis = basis
    }
    enum CodingKeys: String, CodingKey {
        case topics
        case sources
        case basis
    }
}

public struct FeedContext: Codable, Sendable, Hashable {
    public var botID: Int
    public var prompt: String

    public init(botID: Int, prompt: String) {
        self.botID = botID
        self.prompt = prompt
    }
    enum CodingKeys: String, CodingKey {
        case botID = "bot_id"
        case prompt
    }
}

public struct FeedItemState: Codable, Sendable, Hashable {
    public var read: Bool?
    public var saved: Bool?
    public var dismissed: Bool?

    public init(read: Bool? = nil, saved: Bool? = nil, dismissed: Bool? = nil) {
        self.read = read
        self.saved = saved
        self.dismissed = dismissed
    }
    enum CodingKeys: String, CodingKey {
        case read
        case saved
        case dismissed
    }
}

public struct FeedQuery: Sendable, Equatable {
    public var kind: String?
    public var botID: Int?
    public var savedOnly: Bool
    public init(kind: String? = nil, botID: Int? = nil, savedOnly: Bool = false) {
        self.kind = kind; self.botID = botID; self.savedOnly = savedOnly
    }
}

public enum FeedContentKind: String, CaseIterable, Sendable {
    case news, post, video, audio
    public var label: String {
        switch self { case .news: "新闻"; case .post: "短帖"; case .video: "视频"; case .audio: "音频" }
    }
    public var symbol: String {
        switch self { case .news: "newspaper"; case .post: "text.bubble"; case .video: "play.rectangle"; case .audio: "waveform" }
    }
}

public extension FeedItem {
    var evidenceLabel: String { summaryBasis == "body" ? "订阅正文节选" : "来源简介" }
}

/// Incoming source context is always retained alongside any unfinished user question.
public enum FeedChatDraft {
    public static func merging(existing: String, incoming: String?) -> String {
        guard let incoming, !incoming.isEmpty else { return existing }
        return existing.isEmpty ? incoming : existing + "\n\n" + incoming
    }
}
