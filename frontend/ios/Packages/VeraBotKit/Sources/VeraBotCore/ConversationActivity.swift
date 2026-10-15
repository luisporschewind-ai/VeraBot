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
public extension ConversationActivity {
    /// 打开对话即视为全部已读：进入、回到前台、离开对话时把当前全部未读回复一次性上报（按消息去重，取最高修订）。
    /// 不再只依赖「气泡在屏幕上停留 0.5 秒」的可见性判定，避免快速进出后列表圆点和「新」分隔线反复出现。
    var entryReadBatch: [MessagePublication] {
        var best: [Int: Int] = [:]
        for m in unreadMessages { best[m.messageID] = max(best[m.messageID] ?? 0, m.publicationRevision) }
        return best.keys.sorted().map { MessagePublication(messageID: $0, publicationRevision: best[$0]!) }
    }
}
public struct ConversationActivitySnapshot: Codable, Sendable { public let cursor: Int; public let conversations: [ConversationActivity] }
public struct ConversationActivityEvent: Codable, Sendable { public let kind: String; public let conversationID: Int; public let generation: Int; public let conversation: ConversationActivity?; enum CodingKeys: String, CodingKey { case kind, generation, conversation; case conversationID = "conversation_id" } }
public struct ConversationReadResponse: Codable, Sendable { public let cursor: Int; public let conversation: ConversationActivity }

/// Entry labels are frozen until leave. Visibility is tracked per message AND publication revision.
public struct ConversationReadingSession: Sendable {
    public private(set) var newMessageIDs: Set<Int> = []
    /// 「新」分隔线所在的消息：只在进入对话或从后台回到前台时，按当时仍未读的第一条回复确定；
    /// 正在看对话时到达的回复不产生分隔线。离开对话即清除；已读后再次进入不会再出现。
    public private(set) var dividerMessageID: Int?
    private var visibleSince: [String: TimeInterval] = [:]
    public init() {}
    public mutating func enter(_ unread: [MessagePublication]) { leave(); include(unread); dividerMessageID = unread.map(\.messageID).min() }
    public mutating func include(_ unread: [MessagePublication]) { newMessageIDs.formUnion(unread.map(\.messageID)) }
    /// 从后台回到前台：期间到达且仍未读的回复上方显示一次分隔线（已有分隔线时不移动）。
    public mutating func resume(_ unread: [MessagePublication]) {
        include(unread)
        if dividerMessageID == nil { dividerMessageID = unread.map(\.messageID).min() }
    }
    public mutating func leave() { newMessageIDs.removeAll(); dividerMessageID = nil; visibleSince.removeAll() }
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
