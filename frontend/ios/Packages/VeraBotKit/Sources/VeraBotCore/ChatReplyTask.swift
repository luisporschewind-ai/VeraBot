import Foundation

public struct ChatInputRequest: Codable, Sendable, Hashable {
    public let clientRequestID: String
    public let message: String
    public let attachmentIDs: [String]
    public let expectedGeneration: Int
    public init(clientRequestID: String = UUID().uuidString, message: String, attachmentIDs: [String] = [], expectedGeneration: Int) {
        self.clientRequestID = clientRequestID; self.message = message; self.attachmentIDs = attachmentIDs; self.expectedGeneration = expectedGeneration
    }
    enum CodingKeys: String, CodingKey { case clientRequestID = "client_request_id", message, attachmentIDs = "attachment_ids", expectedGeneration = "expected_generation" }
}
public struct ChatReplyTask: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let botID: Int
    public let generation: Int
    public let clientRequestID: String
    public let state: String
    public let phase: String
    public let version: Int
    public let waitID: String?
    public let errorCode: String?
    public let userMessageID: Int
    public let assistantMessageID: Int
    public let content: String
    public let traces: [ToolTrace]
    public let messageStatus: String
    public let publicationRevision: Int
    public var isActive: Bool { ["queued", "running", "awaiting_user", "awaiting_approval"].contains(state) }
    public var executionState: ExecutionState {
        if state == "awaiting_user" || state == "awaiting_approval" { return .awaitingConfirmation }
        if ["failed", "interrupted", "stopped"].contains(state) { return .failed(message: errorCode ?? content) }
        if state == "completed" { return .completed }
        switch phase { case "recalling": return .recalling; case "tool": return .callingTool(name: ""); case "delegating": return .delegating(botName: "", progress: nil); case "replying": return .replying; case "queued": return .idle; default: return .thinking }
    }
    enum CodingKeys: String, CodingKey {
        case id, generation, state, phase, version, content, traces
        case botID = "bot_id", clientRequestID = "client_request_id", waitID = "wait_id", errorCode = "error_code"
        case userMessageID = "user_message_id", assistantMessageID = "assistant_message_id", messageStatus = "message_status", publicationRevision = "publication_revision"
    }
}
public struct ChatInputReceipt: Codable, Sendable {
    public let task: ChatReplyTask
    public let userMessageID: Int
    public let assistantMessageID: Int
    public let generation: Int
    public let cursor: Int
    enum CodingKeys: String, CodingKey { case task, generation, cursor; case userMessageID = "user_message_id", assistantMessageID = "assistant_message_id" }
}
public struct ChatExecutionSnapshot: Codable, Sendable {
    public let generation: Int
    public let cursor: Int
    public let eventCursor: Int
    public let tasks: [ChatReplyTask]
    public init(generation: Int, cursor: Int, eventCursor: Int, tasks: [ChatReplyTask]) { self.generation = generation; self.cursor = cursor; self.eventCursor = eventCursor; self.tasks = tasks }
    enum CodingKeys: String, CodingKey { case generation, cursor, tasks; case eventCursor = "event_cursor" }
}
public struct ChatTaskControl: Codable, Sendable {
    public let task: ChatReplyTask
    public let generation: Int
    public let cursor: Int
}
public struct ChatReplyProjection: Sendable {
    public private(set) var generation = 0
    public private(set) var tasks: [ChatReplyTask] = []
    public init() {}
    public mutating func apply(_ snapshot: ChatExecutionSnapshot) {
        guard snapshot.generation >= generation else { return }
        generation = snapshot.generation; tasks = snapshot.tasks
    }
}
public struct DurableEvent: Sendable {
    public let id: Int
    public let name: String
    public let data: Data
    public init(id: Int, name: String, data: Data) { self.id = id; self.name = name; self.data = data }
}

/// Durable stop/answer identity. A lost control receipt replays precisely the same task/version/wait reference.
public struct ChatControlSubmission: Codable, Sendable, Hashable {
    public let requestID: String
    public let generation: Int
    public let taskID: Int
    public let version: Int
    public let waitID: String?
    public let message: String?
    public init(requestID: String = UUID().uuidString, generation: Int, taskID: Int, version: Int, waitID: String? = nil, message: String? = nil) {
        self.requestID = requestID; self.generation = generation; self.taskID = taskID; self.version = version; self.waitID = waitID; self.message = message
    }
}
