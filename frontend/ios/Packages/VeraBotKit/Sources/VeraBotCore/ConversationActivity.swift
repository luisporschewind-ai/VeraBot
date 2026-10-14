import Foundation

public struct MessagePublication: Codable, Sendable, Hashable {
    public let messageID: Int
    public let publicationRevision: Int
    public init(messageID: Int, publicationRevision: Int) { self.messageID = messageID; self.publicationRevision = publicationRevision }
    enum CodingKeys: String, CodingKey { case messageID = "message_id", publicationRevision = "publication_revision" }
}
public struct ConversationActivity: Codable, Sendable, Identifiable {
    public let kind: String
    public let conversationID: Int
    public let generation: Int
    public let revision: Int
    public let state: String
    public let phase: String
    public let unreadCount: Int
    public let pendingCount: Int
    public let unreadMessages: [MessagePublication]
    public let workItems: [WorkItem]
    public let latestMessage: LatestMessage?
    public var id: String { "\(kind):\(conversationID)" }
    public struct WorkItem: Codable, Sendable { public let id: Int; public let state: String; public let phase: String; public let version: Int; public let waitID: String?; public let source: String; public let ownerMemberID: Int?
        enum CodingKeys: String, CodingKey { case id, state, phase, version, source; case waitID = "wait_id", ownerMemberID = "owner_member_id" }
    }
    public struct LatestMessage: Codable, Sendable { public let id: Int; public let content: String; public let createdAt: String?; enum CodingKeys: String, CodingKey { case id, content; case createdAt = "created_at" } }
    public static func unreadLabel(_ count: Int) -> String { count > 99 ? "99+" : String(max(0, count)) }
    public var statusText: String {
        if state == "awaiting_user" { return "等你补充" }
        if state == "awaiting_approval" { return "待你确认" }
        if ["failed", "interrupted", "stopped"].contains(state) { return "工作暂未完成" }
        switch phase { case "queued": return "排队中"; case "recalling": return "正在整理上下文"; case "thinking": return "正在思考"; case "tool": return "正在查询／处理"; case "delegating": return "正在协作"; case "replying": return "正在回复"; case "retry_wait": return "正在重连"; default: return "" }
    }
    enum CodingKeys: String, CodingKey { case kind, generation, revision, state, phase; case conversationID = "conversation_id", unreadCount = "unread_count", pendingCount = "pending_count", unreadMessages = "unread_messages", workItems = "work_items", latestMessage = "latest_message" }
}
public struct ConversationActivitySnapshot: Codable, Sendable { public let cursor: Int; public let conversations: [ConversationActivity] }
public struct ConversationActivityEvent: Codable, Sendable { public let kind: String; public let conversationID: Int; public let generation: Int; public let conversation: ConversationActivity?; enum CodingKeys: String, CodingKey { case kind, generation, conversation; case conversationID = "conversation_id" } }
public struct ConversationReadResponse: Codable, Sendable { public let cursor: Int; public let conversation: ConversationActivity }

/// Entry labels are frozen until leave. Visibility is tracked per message AND publication revision.
public struct ConversationReadingSession: Sendable {
    public private(set) var newMessageIDs: Set<Int> = []
    private var visibleSince: [String: TimeInterval] = [:]
    public init() {}
    public mutating func enter(_ unread: [MessagePublication]) { leave(); include(unread) }
    public mutating func include(_ unread: [MessagePublication]) { newMessageIDs.formUnion(unread.map(\.messageID)) }
    /// 本次未读里最早的一条前面放「新消息」分隔线。单条也放；其余消息不再另挂未读提示。
    public func showsNewMessagesDivider(messageID: Int) -> Bool { newMessageIDs.min() == messageID }
    public mutating func leave() { newMessageIDs.removeAll(); visibleSince.removeAll() }
    public mutating func suspend() { visibleSince.removeAll() }
    public mutating func observe(messageID: Int, revision: Int, visibleFraction: Double, foreground: Bool, pageVisible: Bool, now: TimeInterval) -> Bool {
        let key = "\(messageID):\(revision)"
        guard foreground, pageVisible, revision > 0, visibleFraction >= 0.25 else { visibleSince.removeValue(forKey: key); return false }
        if let start = visibleSince[key] { return now - start >= 0.5 }
        visibleSince[key] = now; return false
    }
}

public enum ConversationVisibilityPolicy {
    public static func isVisible(bodyHeight: Double, viewportHeight: Double, intersectionHeight: Double) -> Bool {
        guard bodyHeight > 0, viewportHeight > 0 else { return false }
        return intersectionHeight >= min(24, bodyHeight * 0.5) && intersectionHeight >= min(bodyHeight, viewportHeight) * 0.25
    }
}
