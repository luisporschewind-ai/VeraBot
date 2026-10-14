import Foundation
import VeraBotCore
import VeraBotPersistence

/// This database is already isolated by server/account in AppState. No network callback may revive a closed scope.
public actor ConversationActivityRepository {
    private let database: LocalDatabase
    private let sessionIsCurrent: @Sendable () -> Bool
    private var invalidated = false
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(database: LocalDatabase, sessionIsCurrent: @escaping @Sendable () -> Bool = { true }) { self.database = database; self.sessionIsCurrent = sessionIsCurrent }
    public func invalidate() { invalidated = true }
    private func check() throws { guard !invalidated, sessionIsCurrent() else { throw CancellationError() }; try Task.checkCancellation() }
    private func prepare() throws {
        try check()
        try database.execute("CREATE TABLE IF NOT EXISTS continuity_cache(key TEXT PRIMARY KEY, snapshot BLOB NOT NULL)")
        try database.execute("CREATE TABLE IF NOT EXISTS chat_pending(bot_id INTEGER NOT NULL, request_id TEXT NOT NULL, generation INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(bot_id,request_id))")
        try database.execute("CREATE TABLE IF NOT EXISTS read_outbox(kind TEXT NOT NULL, conversation_id INTEGER NOT NULL, generation INTEGER NOT NULL, message_id INTEGER NOT NULL, revision INTEGER NOT NULL, PRIMARY KEY(kind,conversation_id,generation,message_id))")
    }
    public func savePending(_ input: ChatInputRequest, botID: Int) throws {
        try prepare()
        let payload = try encoder.encode(input)
        if let existing = try pending(botID: botID).first(where: { $0.clientRequestID == input.clientRequestID }), existing != input { throw PersistenceError.sqlite("request identity already has a different payload") }
        try database.execute("INSERT OR IGNORE INTO chat_pending(bot_id,request_id,generation,payload) VALUES(?,?,?,?)", values: [botID,input.clientRequestID,input.expectedGeneration,payload])
    }
    public func pending(botID: Int) throws -> [ChatInputRequest] {
        try prepare()
        return try database.rows("SELECT payload FROM chat_pending WHERE bot_id=? ORDER BY rowid", values: [botID]).compactMap { row in guard let data = row["payload"] as? Data else { return nil }; return try decoder.decode(ChatInputRequest.self, from: data) }
    }
    public func removePending(botID: Int, requestID: String) throws { try prepare(); try database.execute("DELETE FROM chat_pending WHERE bot_id=? AND request_id=?", values: [botID,requestID]) }
    public func reconcileGeneration(botID: Int, generation: Int) throws {
        try prepare()
        try save(pendingControls(botID: botID).filter { $0.generation == generation }, key: "controls:\(botID)")
        try database.transaction { db in
            try db.execute("DELETE FROM chat_pending WHERE bot_id=? AND generation<>?", values: [botID,generation])
            try db.execute("DELETE FROM read_outbox WHERE kind='private' AND conversation_id=? AND generation<>?", values: [botID,generation])
        }
    }
    public func pendingControls(botID: Int) throws -> [ChatControlSubmission] { try cached([ChatControlSubmission].self, key: "controls:\(botID)") ?? [] }
    public func saveControl(_ control: ChatControlSubmission, botID: Int) throws {
        var pending = try pendingControls(botID: botID)
        if let existing = pending.first(where: { $0.requestID == control.requestID }) {
            guard existing == control else { throw PersistenceError.sqlite("control identity already has a different payload") }
            return
        }
        pending.append(control); try save(pending, key: "controls:\(botID)")
    }
    public func removeControl(botID: Int, requestID: String) throws { try save(pendingControls(botID: botID).filter { $0.requestID != requestID }, key: "controls:\(botID)") }
    public func save<Value: Codable & Sendable>(_ value: Value, key: String) throws { try prepare(); try database.execute("INSERT INTO continuity_cache(key,snapshot) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET snapshot=excluded.snapshot", values: [key,try encoder.encode(value)]) }
    public func cached<Value: Codable & Sendable>(_ type: Value.Type, key: String) throws -> Value? { try prepare(); guard let data = try database.rows("SELECT snapshot FROM continuity_cache WHERE key=?", values: [key]).first?["snapshot"] as? Data else { return nil }; return try decoder.decode(type, from: data) }
    public func enqueueRead(kind: String, id: Int, generation: Int, message: MessagePublication) throws {
        try prepare(); guard message.publicationRevision > 0 else { return }
        try database.execute("INSERT INTO read_outbox(kind,conversation_id,generation,message_id,revision) VALUES(?,?,?,?,?) ON CONFLICT(kind,conversation_id,generation,message_id) DO UPDATE SET revision=MAX(revision,excluded.revision)", values: [kind,id,generation,message.messageID,message.publicationRevision])
    }
    public func readOutbox(kind: String, id: Int, generation: Int) throws -> [MessagePublication] { try prepare(); return try database.rows("SELECT message_id,revision FROM read_outbox WHERE kind=? AND conversation_id=? AND generation=? ORDER BY message_id", values: [kind,id,generation]).compactMap { row in guard let messageID = row["message_id"] as? Int, let revision = row["revision"] as? Int else { return nil }; return MessagePublication(messageID: messageID, publicationRevision: revision) } }
    public func acknowledgeReads(kind: String, id: Int, generation: Int, messages: [MessagePublication]) throws {
        try prepare()
        try database.transaction { db in for message in messages { try db.execute("DELETE FROM read_outbox WHERE kind=? AND conversation_id=? AND generation=? AND message_id=? AND revision<=?", values: [kind,id,generation,message.messageID,message.publicationRevision]) } }
    }
}
