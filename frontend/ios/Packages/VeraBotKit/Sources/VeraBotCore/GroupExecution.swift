import Foundation

public struct GroupInputRequest: Codable, Sendable, Hashable {
    public var clientRequestID: UUID
    public var message: String
    public var targetMemberIDs: [Int]
    public var everyone: Bool
    public var replyToMessageID: Int?
    public var attachmentIDs: [String]
    public var expectedTaskID: Int?
    public var expectedVersion: Int?
    public var clarificationID: Int?
    enum CodingKeys: String, CodingKey {
        case message, everyone
        case clientRequestID = "client_request_id", targetMemberIDs = "target_member_ids"
        case replyToMessageID = "reply_to_message_id", attachmentIDs = "attachment_ids"
        case expectedTaskID = "expected_task_id", expectedVersion = "expected_version", clarificationID = "clarification_id"
    }
    public init(clientRequestID: UUID = UUID(), message: String, targetMemberIDs: [Int] = [], everyone: Bool = false,
                replyToMessageID: Int? = nil, attachmentIDs: [String] = [], expectedTaskID: Int? = nil,
                expectedVersion: Int? = nil, clarificationID: Int? = nil) {
        self.clientRequestID = clientRequestID; self.message = message
        self.targetMemberIDs = everyone ? [] : targetMemberIDs.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        self.everyone = everyone; self.replyToMessageID = replyToMessageID; self.attachmentIDs = attachmentIDs
        self.expectedTaskID = expectedTaskID; self.expectedVersion = expectedVersion; self.clarificationID = clarificationID
    }
}

public enum GroupTaskStatus: String, Codable, Sendable, Hashable {
    case queued, running, awaitingUser = "awaiting_user", completed, stopped, failed, interrupted
    public var canStop: Bool { [.queued,.running,.awaitingUser].contains(self) }
    public var canResume: Bool { [.stopped,.failed,.interrupted].contains(self) }
}

public struct GroupTask: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let groupID: Int
    public let goal: String
    public var state: GroupTaskStatus
    public var version: Int
    public var ownerMemberID: Int?
    public let rootMessageID: Int?
    public let createdAt: String
    public var updatedAt: String
    public let finishedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, goal, state, version
        case groupID = "group_id", ownerMemberID = "owner_member_id", rootMessageID = "root_message_id"
        case createdAt = "created_at", updatedAt = "updated_at", finishedAt = "finished_at"
    }
    public init(id: Int, groupID: Int, goal: String, state: GroupTaskStatus, version: Int, ownerMemberID: Int? = nil,
                rootMessageID: Int? = nil, createdAt: String = "", updatedAt: String = "", finishedAt: String? = nil) {
        self.id = id; self.groupID = groupID; self.goal = goal; self.state = state; self.version = version
        self.ownerMemberID = ownerMemberID; self.rootMessageID = rootMessageID
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.finishedAt = finishedAt
    }
}

public struct GroupClarification: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let taskID: Int
    public let groupID: Int
    public var ownerMemberID: Int?
    public let originalRequest: String
    public var missingInformation: [String]
    public var latestQuestionMessageID: Int?
    public var status: String
    public let createdAt: String
    public var updatedAt: String
    enum CodingKeys: String, CodingKey {
        case id, status
        case taskID = "task_id", groupID = "group_id", ownerMemberID = "owner_member_id"
        case originalRequest = "original_request", missingInformation = "missing_information"
        case latestQuestionMessageID = "latest_question_message_id", createdAt = "created_at", updatedAt = "updated_at"
    }
    public init(id: Int, taskID: Int, groupID: Int, ownerMemberID: Int? = nil, originalRequest: String = "",
                missingInformation: [String] = [], latestQuestionMessageID: Int? = nil, status: String = "open",
                createdAt: String = "", updatedAt: String = "") {
        self.id = id; self.taskID = taskID; self.groupID = groupID; self.ownerMemberID = ownerMemberID
        self.originalRequest = originalRequest; self.missingInformation = missingInformation
        self.latestQuestionMessageID = latestQuestionMessageID; self.status = status
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct GroupExecutionSnapshot: Codable, Sendable, Hashable {
    public var task: GroupTask?
    public var clarification: GroupClarification?
    public var eventCursor: Int
    public var messages: [GroupMessage]?
    enum CodingKeys: String, CodingKey { case task, clarification, messages; case eventCursor = "event_cursor" }
    public init(task: GroupTask? = nil, clarification: GroupClarification? = nil, eventCursor: Int = 0, messages: [GroupMessage]? = nil) {
        self.task = task; self.clarification = clarification; self.eventCursor = eventCursor; self.messages = messages
    }
}

public struct GroupInputReceipt: Codable, Sendable, Hashable {
    public let task: GroupTask
    public let inputID: Int
    public let turnID: Int
    public let eventCursor: Int
    enum CodingKeys: String, CodingKey { case task; case inputID = "input_id", turnID = "turn_id", eventCursor = "event_cursor" }
    public init(task: GroupTask, inputID: Int, turnID: Int, eventCursor: Int) {
        self.task = task; self.inputID = inputID; self.turnID = turnID; self.eventCursor = eventCursor
    }
}

public struct GroupInputLookup: Codable, Sendable, Hashable {
    public let task: GroupTask
    public let inputID: Int
    public let turnID: Int
    public let eventCursor: Int
    enum CodingKeys: String, CodingKey { case task; case inputID = "input_id", turnID = "turn_id", eventCursor = "event_cursor" }
}

public struct GroupExecutionEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public var groupID: Int
    public let taskID: Int?
    public let version: Int
    public let kind: String
    public let payload: JSONValue
    public let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, version, kind, payload
        case groupID = "group_id", taskID = "task_id", createdAt = "created_at"
    }
    public init(id: Int, groupID: Int, taskID: Int?, version: Int, kind: String, payload: JSONValue, createdAt: String) {
        self.id = id; self.groupID = groupID; self.taskID = taskID; self.version = version
        self.kind = kind; self.payload = payload; self.createdAt = createdAt
    }
}

public struct GroupExecutionViewState: Sendable, Hashable {
    public var snapshot: GroupExecutionSnapshot
    public var messages: [GroupMessage]
    public init(snapshot: GroupExecutionSnapshot = .init(), messages: [GroupMessage] = []) {
        self.snapshot = snapshot; self.messages = messages
    }
}

public struct GroupTaskCommand: Codable, Sendable, Hashable {
    public let clientRequestID: UUID
    public let expectedVersion: Int
    public let message: String
    enum CodingKeys: String, CodingKey { case clientRequestID = "client_request_id", expectedVersion = "expected_version", message }
    public init(clientRequestID: UUID = UUID(), expectedVersion: Int, message: String = "") {
        self.clientRequestID = clientRequestID; self.expectedVersion = expectedVersion; self.message = message
    }
}
