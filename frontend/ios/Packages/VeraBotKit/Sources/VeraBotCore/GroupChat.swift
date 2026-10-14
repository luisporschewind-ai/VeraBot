import Foundation

public struct ChatGroupMember: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let botID: Int?
    public let name: String
    public let color: String
    public let detail: String
    public let avatar: String?
    public let appearance: JSONValue?
    public let available: Bool
    enum CodingKeys: String, CodingKey { case id, name, color, detail, avatar, appearance, available; case botID = "bot_id" }
    public init(id: Int, botID: Int?, name: String, color: String, detail: String,
                avatar: String? = nil, appearance: JSONValue? = nil, available: Bool = true) {
        self.id = id; self.botID = botID; self.name = name; self.color = color; self.detail = detail
        self.avatar = avatar; self.appearance = appearance; self.available = available
    }
}

public struct ChatGroup: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var name: String
    public let members: [ChatGroupMember]
    public let readOnly: Bool
    public let createdAt: String?
    public let updatedAt: String?
    public let activeTurnID: Int?
    public let lastMessage: GroupMessage?
    enum CodingKeys: String, CodingKey {
        case id, name, members
        case activeTurnID = "active_turn_id", lastMessage = "last_message"
        case readOnly = "read_only", createdAt = "created_at", updatedAt = "updated_at"
    }
    public init(id: Int, name: String, members: [ChatGroupMember]) {
        self.id = id; self.name = name; self.members = members
        activeTurnID = nil; lastMessage = nil
        readOnly = !members.contains { $0.available && $0.botID != nil }; createdAt = nil; updatedAt = nil
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        members = try c.decode([ChatGroupMember].self, forKey: .members)
        activeTurnID = try c.decodeIfPresent(Int.self, forKey: .activeTurnID)
        lastMessage = try c.decodeIfPresent(GroupMessage.self, forKey: .lastMessage)
        readOnly = try c.decode(Bool.self, forKey: .readOnly)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(members, forKey: .members)
        try c.encodeIfPresent(activeTurnID, forKey: .activeTurnID); try c.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try c.encode(readOnly, forKey: .readOnly)
        try c.encodeIfPresent(createdAt, forKey: .createdAt); try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

public enum GroupMessageStatus: String, Codable, Sendable { case completed, streaming, failed, stopped, interrupted }
public enum GroupMessageRole: String, Codable, Sendable { case user, bot }
public enum GroupTurnStatus: String, Codable, Sendable { case running, completed, partial, stopped, failed, interrupted }
public enum GroupChatMode: String, Codable, Sendable { case auto, single, round }

public struct GroupMessage: Codable, Sendable, Hashable, Identifiable {
    public var generation: Int?
    public var publicationRevision: Int?
    public let id: Int
    public let groupID: Int
    public let turnID: Int
    public let memberID: Int?
    public let taskID: Int?
    public let taskVersion: Int?
    public let retryOfMessageID: Int?
    public let role: GroupMessageRole
    public var content: String
    public var status: GroupMessageStatus
    public let senderName: String?
    public let senderAppearance: JSONValue?
    public let usage: JSONValue?
    public let createdAt: String?
    public let finishedAt: String?
    public let attachments: [Attachment]
    enum CodingKeys: String, CodingKey {
        case id, role, content, status, usage
        case generation, publicationRevision = "publication_revision"
        case taskID = "task_id", taskVersion = "task_version"
        case retryOfMessageID = "retry_of_message_id"
        case groupID = "group_id", turnID = "turn_id", memberID = "member_id", senderName = "sender_name"
        case senderAppearance = "sender_appearance", createdAt = "created_at", finishedAt = "finished_at", attachments
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generation = try c.decodeIfPresent(Int.self, forKey: .generation)
        publicationRevision = try c.decodeIfPresent(Int.self, forKey: .publicationRevision)
        id = try c.decode(Int.self, forKey: .id)
        groupID = try c.decodeIfPresent(Int.self, forKey: .groupID) ?? 0
        turnID = try c.decodeIfPresent(Int.self, forKey: .turnID) ?? 0
        memberID = try c.decodeIfPresent(Int.self, forKey: .memberID)
        taskID = try c.decodeIfPresent(Int.self, forKey:.taskID)
        taskVersion = try c.decodeIfPresent(Int.self, forKey:.taskVersion)
        retryOfMessageID = try c.decodeIfPresent(Int.self, forKey: .retryOfMessageID)
        role = try c.decodeIfPresent(GroupMessageRole.self, forKey: .role) ?? (memberID == nil ? .user : .bot)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        status = try c.decodeIfPresent(GroupMessageStatus.self, forKey: .status) ?? .completed
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName)
        senderAppearance = try c.decodeIfPresent(JSONValue.self, forKey: .senderAppearance)
        usage = try c.decodeIfPresent(JSONValue.self, forKey: .usage)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        finishedAt = try c.decodeIfPresent(String.self, forKey: .finishedAt)
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
    }
    public init(id: Int, memberID: Int?, content: String, status: GroupMessageStatus = .completed,
                groupID: Int = 0, turnID: Int = 0, role: GroupMessageRole? = nil, attachments: [Attachment] = [], taskID: Int? = nil, taskVersion: Int? = nil) {
        self.generation = nil; self.publicationRevision = nil
        self.id = id; self.memberID = memberID; self.content = content; self.status = status
        self.groupID = groupID; self.turnID = turnID; self.role = role ?? (memberID == nil ? .user : .bot)
        retryOfMessageID = nil; senderName = nil; senderAppearance = nil; usage = nil; createdAt = nil; finishedAt = nil
        self.attachments = attachments;self.taskID = taskID;self.taskVersion = taskVersion
    }
}

public struct GroupTurn: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let groupID: Int
    public let clientRequestID: UUID
    public let mode: GroupChatMode
    public let status: GroupTurnStatus
    public let cancelRequested: Bool
    public let messages: [GroupMessage]
    public let targetMemberID: Int?
    public let userMessageID: Int?
    public let retryOfMessageID: Int?
    public let contextEndMessageID: Int?
    public let createdAt: String?
    public let finishedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, mode, status, messages
        case groupID = "group_id", clientRequestID = "client_request_id", cancelRequested = "cancel_requested"
        case targetMemberID = "target_member_id", userMessageID = "user_message_id", retryOfMessageID = "retry_of_message_id"
        case contextEndMessageID = "context_end_message_id", createdAt = "created_at", finishedAt = "finished_at"
    }
}
public struct GroupListResponse: Decodable, Sendable { public let groups: [ChatGroup] }
public struct GroupMessagesResponse: Decodable, Sendable {
    public let messages: [GroupMessage]
    public let nextBeforeID: Int?
    enum CodingKeys: String, CodingKey { case messages; case nextBeforeID = "next_before_id" }
}
public struct GroupMessagesSyncResponse: Decodable, Sendable {
    public let revision: Int64
    public let messages: [GroupMessage]
    public let nextBeforeID: Int?
    public let unchanged: Bool
    enum CodingKeys: String, CodingKey { case revision, messages, unchanged; case nextBeforeID = "next_before_id" }
}
public struct GroupCreateRequest: Encodable, Sendable {
    public let name: String; public let botIDs: [Int]
    public init(name: String, botIDs: [Int]) { self.name = name; self.botIDs = botIDs }
    enum CodingKeys: String, CodingKey { case name; case botIDs = "bot_ids" }
}
public struct GroupUpdateRequest: Encodable, Sendable {
    public let name: String?
    public init(name: String? = nil) { self.name = name }
    enum CodingKeys: String, CodingKey { case name }
}
public struct GroupChatRequest: Encodable, Sendable {
    public let clientRequestID: UUID; public let message: String; public let mode: GroupChatMode; public let targetBotID: Int?
    public let attachmentIDs: [String]
    public init(clientRequestID: UUID = UUID(), message: String, mode: GroupChatMode = .auto, targetBotID: Int? = nil,
                attachmentIDs: [String] = []) {
        self.clientRequestID = clientRequestID; self.message = message; self.mode = mode; self.targetBotID = targetBotID
        self.attachmentIDs = attachmentIDs
    }
    enum CodingKeys: String, CodingKey { case message, mode, attachmentIDs = "attachment_ids"; case clientRequestID = "client_request_id", targetBotID = "target_bot_id" }
}

/// Every event belongs to exactly one group and one turn; private ChatEvent stays separate.
public struct GroupChatEvent: Sendable, Hashable {
    public let groupID: Int
    public let turnID: Int
    public let payload: Payload
    public enum Payload: Sendable, Hashable {
        case turnStart(userMessage: GroupMessage, speakerMemberIDs: [Int])
        case messageStart(GroupMessage)
        case status(messageID: Int, memberID: Int, phase: String)
        case delta(messageID: Int, memberID: Int, text: String)
        case messageDone(GroupMessage)
        case error(code: String, message: String, messageID: Int?)
        case turnDone(status: GroupTurnStatus, usage: JSONValue?, messageIDs: [Int])
    }
    public init(groupID: Int, turnID: Int, payload: Payload) { self.groupID = groupID; self.turnID = turnID; self.payload = payload }
}
