import Foundation

public struct StoredMessage<Value: Codable & Sendable>: Sendable {
    public let localID: String
    public let remoteID: Int?
    public let status: String
    public let sortKey: Int
    public init(localID: String, remoteID: Int?, status: String, sortKey: Int, value: Value) {
        self.localID = localID; self.remoteID = remoteID; self.status = status; self.sortKey = sortKey; self.value = value
    }
    public let value: Value
}

/// Typed Codable boundary over LocalDatabase. The actor never exposes a raw SQLite handle.
public actor ConversationStore {
    public let database: LocalDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: LocalDatabase) { self.database = database }

    public func saveConversation<Value: Codable & Sendable>(_ value: Value, kind: String, id: Int) async throws {
        let data = try encoder.encode(value)
        try database.execute("INSERT INTO conversations(kind,remote_id,snapshot,updated_at) VALUES(?,?,?,?) ON CONFLICT(kind,remote_id) DO UPDATE SET snapshot=excluded.snapshot,updated_at=excluded.updated_at",
                                   values: [kind, id, data, Date().timeIntervalSince1970])
    }

    public func conversations<Value: Codable & Sendable>(_ type: Value.Type, kind: String) async throws -> [Value] {
        try database.rows("SELECT snapshot FROM conversations WHERE kind=? ORDER BY updated_at DESC,remote_id DESC", values: [kind]).compactMap {
            guard let data = $0["snapshot"] as? Data else { return nil }
            return try decoder.decode(type, from: data)
        }
    }

    public func replaceConversations<Value: Codable & Sendable>(_ values: [Value], kind: String,
                                                                id: @Sendable (Value) -> Int) async throws {
        let encoded = try values.map { (id: id($0), data: try encoder.encode($0)) }
        try database.transaction { db in
            let rows = try db.rows("SELECT remote_id FROM conversations WHERE kind=?", values: [kind])
            let incoming = Set(encoded.map(\.id))
            for row in rows {
                if let existing = row["remote_id"] as? Int, !incoming.contains(existing) {
                    for table in ["messages", "drafts", "card_states", "sync_state", "sync_staging"] {
                        try db.execute("DELETE FROM \(table) WHERE kind=? AND conversation_id=?", values: [kind == "bot" ? "private" : kind, existing])
                    }
                    try db.execute("DELETE FROM conversations WHERE kind=? AND remote_id=?", values: [kind, existing])
                }
            }
            for item in encoded {
                try db.execute("INSERT INTO conversations(kind,remote_id,snapshot,updated_at) VALUES(?,?,?,?) ON CONFLICT(kind,remote_id) DO UPDATE SET snapshot=excluded.snapshot,updated_at=excluded.updated_at",
                                     values: [kind, item.id, item.data, Date().timeIntervalSince1970])
            }
        }
    }

    public func saveMessage<Value: Codable & Sendable>(_ value: Value, kind: String, conversationID: Int,
                                                        localID: String = UUID().uuidString, remoteID: Int?,
                                                        sortKey: Int, status: String) async throws -> String {
        let data = try encoder.encode(value)
        let existing: String? = if let remoteID {
            try database.rows("SELECT local_id FROM messages WHERE kind=? AND conversation_id=? AND remote_id=?",
                                    values: [kind, conversationID, remoteID]).first?["local_id"] as? String
        } else { nil }
        let key = existing ?? localID
        try database.execute("""
                                     INSERT INTO messages(local_id,kind,conversation_id,remote_id,sort_key,snapshot,local_status)
                                     VALUES(?,?,?,?,?,?,?) ON CONFLICT(local_id) DO UPDATE SET remote_id=excluded.remote_id,
                                     sort_key=excluded.sort_key,snapshot=excluded.snapshot,local_status=excluded.local_status
                                     """,
                                   values: [key, kind, conversationID, remoteID, sortKey, data, status])
        return key
    }

    public func deleteMessage(localID: String, kind: String, conversationID: Int, remoteID: Int? = nil) async throws {
        try database.transaction { db in
            if let remoteID {
                try db.execute("DELETE FROM messages WHERE remote_id=? AND kind=? AND conversation_id=?",
                               values: [remoteID, kind, conversationID])
            } else {
                try db.execute("DELETE FROM messages WHERE local_id=? AND kind=? AND conversation_id=?",
                               values: [localID, kind, conversationID])
            }
            // Invalidate any in-flight snapshot. Its final commit checks this marker.
            try db.execute("DELETE FROM sync_staging WHERE kind=? AND conversation_id=?", values: [kind, conversationID])
            try db.execute("DELETE FROM sync_state WHERE kind=? AND conversation_id=?", values: [kind, conversationID])
        }
    }

    public func messages<Value: Codable & Sendable>(_ type: Value.Type, kind: String, conversationID: Int,
                                                      before: Int? = nil, limit: Int = 100) async throws -> [StoredMessage<Value>] {
        let sql = before == nil
            ? "SELECT local_id,remote_id,sort_key,local_status,snapshot FROM messages WHERE kind=? AND conversation_id=? ORDER BY sort_key DESC,local_id DESC LIMIT ?"
            : "SELECT local_id,remote_id,sort_key,local_status,snapshot FROM messages WHERE kind=? AND conversation_id=? AND sort_key<? ORDER BY sort_key DESC,local_id DESC LIMIT ?"
        let values = SQLiteValues(before.map { [kind, conversationID, $0, limit] } ?? [kind, conversationID, limit])
        return try database.rows(sql, values: values).reversed().compactMap { row in
            guard let id = row["local_id"] as? String, let data = row["snapshot"] as? Data else { return nil }
            return StoredMessage(localID: id, remoteID: row["remote_id"] as? Int,
                                 status: row["local_status"] as? String ?? "synced",
                                 sortKey: row["sort_key"] as? Int ?? 0,
                                 value: try decoder.decode(type, from: data))
        }
    }

    public func saveDraft(_ text: String, kind: String, conversationID: Int) async throws {
        if text.isEmpty {
            try database.execute("DELETE FROM drafts WHERE kind=? AND conversation_id=?", values: [kind, conversationID])
        } else {
            try database.execute("INSERT INTO drafts(kind,conversation_id,text,updated_at) VALUES(?,?,?,?) ON CONFLICT(kind,conversation_id) DO UPDATE SET text=excluded.text,updated_at=excluded.updated_at",
                                       values: [kind, conversationID, text, Date().timeIntervalSince1970])
        }
    }

    public func draft(kind: String, conversationID: Int) async throws -> String {
        try database.rows("SELECT text FROM drafts WHERE kind=? AND conversation_id=?", values: [kind, conversationID]).first?["text"] as? String ?? ""
    }

    public func syncState(kind: String, conversationID: Int) async throws -> (revision: Int64?, activeRevision: Int64?, beforeID: Int?, complete: Bool) {
        guard let row = try database.rows("SELECT completed_revision,active_revision,next_before_id,complete FROM sync_state WHERE kind=? AND conversation_id=?",
                                                values: [kind, conversationID]).first else { return (nil, nil, nil, false) }
        return ((row["completed_revision"] as? Int).map(Int64.init), (row["active_revision"] as? Int).map(Int64.init),
                row["next_before_id"] as? Int, (row["complete"] as? Int ?? 0) != 0)
    }

    public func stagedMessages<Value: Codable & Sendable>(_ type: Value.Type, kind: String,
                                                            conversationID: Int, revision: Int64) async throws -> [(id: Int, value: Value)] {
        try database.rows("SELECT remote_id,snapshot FROM sync_staging WHERE kind=? AND conversation_id=? AND revision=? ORDER BY remote_id",
                                values: [kind, conversationID, revision]).compactMap { row in
            guard let id = row["remote_id"] as? Int, let data = row["snapshot"] as? Data else { return nil }
            return (id, try decoder.decode(type, from: data))
        }
    }

    public func restartSync(kind: String, conversationID: Int) async throws {
        try database.transaction { db in
            try db.execute("DELETE FROM sync_staging WHERE kind=? AND conversation_id=?", values: [kind, conversationID])
            try db.execute("DELETE FROM sync_state WHERE kind=? AND conversation_id=?", values: [kind, conversationID])
        }
    }

    public func stage<Value: Codable & Sendable>(_ value: Value, kind: String, conversationID: Int,
                                                  revision: Int64, remoteID: Int, nextBeforeID: Int?) async throws {
        let data = try encoder.encode(value)
        try database.transaction { db in
            try db.execute("INSERT OR REPLACE INTO sync_staging(kind,conversation_id,revision,remote_id,snapshot) VALUES(?,?,?,?,?)",
                                 values: [kind, conversationID, revision, remoteID, data])
            try db.execute("INSERT INTO sync_state(kind,conversation_id,active_revision,next_before_id,complete) VALUES(?,?,?,?,0) ON CONFLICT(kind,conversation_id) DO UPDATE SET active_revision=excluded.active_revision,next_before_id=excluded.next_before_id,complete=0",
                                 values: [kind, conversationID, revision, nextBeforeID])
        }
    }

    public func stagePage<Value: Codable & Sendable>(_ values: [(id: Int, value: Value)], kind: String,
                                                      conversationID: Int, revision: Int64,
                                                      nextBeforeID: Int?) async throws {
        let encoded = try values.map { (id: $0.id, data: try encoder.encode($0.value)) }
        try database.transaction { db in
            for item in encoded {
                try db.execute("INSERT OR REPLACE INTO sync_staging(kind,conversation_id,revision,remote_id,snapshot) VALUES(?,?,?,?,?)",
                               values: [kind, conversationID, revision, item.id, item.data])
            }
            try db.execute("INSERT INTO sync_state(kind,conversation_id,active_revision,next_before_id,complete) VALUES(?,?,?,?,0) ON CONFLICT(kind,conversation_id) DO UPDATE SET active_revision=excluded.active_revision,next_before_id=excluded.next_before_id,complete=0",
                           values: [kind, conversationID, revision, nextBeforeID])
        }
    }

    @discardableResult
    public func finishSnapshot<Value: Codable & Sendable>(_ values: [Value], remoteIDs: [Int], kind: String,
                                                           conversationID: Int, revision: Int64,
                                                           sortKey: @Sendable (Value) -> Int,
                                                           id: @Sendable (Value) -> Int) async throws -> Bool {
        let encoded = try values.map { (id: id($0), sort: sortKey($0), data: try encoder.encode($0)) }
        return try database.transaction { db in
            let active = try db.rows("SELECT active_revision FROM sync_state WHERE kind=? AND conversation_id=?",
                                     values: [kind, conversationID]).first?["active_revision"] as? Int
            guard active == Int(revision) else { return false }
            let rows = try db.rows("SELECT local_id,remote_id FROM messages WHERE kind=? AND conversation_id=? AND remote_id IS NOT NULL",
                                         values: [kind, conversationID])
            let incoming = Set(remoteIDs)
            for row in rows {
                if let remote = row["remote_id"] as? Int, !incoming.contains(remote),
                   let local = row["local_id"] as? String {
                    try db.execute("DELETE FROM messages WHERE local_id=?", values: [local])
                }
            }
            for item in encoded {
                let data = item.data
                let remote = item.id
                let existing = try db.rows("SELECT local_id FROM messages WHERE kind=? AND conversation_id=? AND remote_id=?",
                                                 values: [kind, conversationID, remote]).first?["local_id"] as? String
                try db.execute("""
                                         INSERT INTO messages(local_id,kind,conversation_id,remote_id,sort_key,snapshot,local_status)
                                         VALUES(?,?,?,?,?,?,'synced') ON CONFLICT(kind,conversation_id,remote_id) DO UPDATE SET
                                         sort_key=excluded.sort_key,snapshot=excluded.snapshot,local_status='synced'
                                         """,
                                     values: [existing ?? UUID().uuidString, kind, conversationID, remote, item.sort, data])
            }
            try db.execute("DELETE FROM sync_staging WHERE kind=? AND conversation_id=?", values: [kind, conversationID])
            try db.execute("INSERT INTO sync_state(kind,conversation_id,completed_revision,active_revision,next_before_id,complete) VALUES(?,?,?,NULL,NULL,1) ON CONFLICT(kind,conversation_id) DO UPDATE SET completed_revision=excluded.completed_revision,active_revision=NULL,next_before_id=NULL,complete=1",
                                 values: [kind, conversationID, revision])
            return true
        }
    }

    public func isComplete(kind: String, conversationID: Int) async throws -> Bool {
            (try database.rows("SELECT complete FROM sync_state WHERE kind=? AND conversation_id=?", values: [kind, conversationID]).first?["complete"] as? Int ?? 0) != 0
    }

    public func markComplete(kind: String, conversationID: Int, revision: Int64) async throws {
        try database.execute("INSERT INTO sync_state(kind,conversation_id,completed_revision,complete) VALUES(?,?,?,1) ON CONFLICT(kind,conversation_id) DO UPDATE SET completed_revision=excluded.completed_revision,active_revision=NULL,next_before_id=NULL,complete=1",
                             values: [kind, conversationID, revision])
    }

    public func deleteConversation(kind: String, id: Int) async throws {
        try database.transaction { db in
            for table in ["messages", "drafts", "card_states", "sync_state", "sync_staging"] {
                try db.execute("DELETE FROM \(table) WHERE kind=? AND conversation_id=?", values: [kind, id])
            }
            try db.execute("DELETE FROM conversations WHERE kind=? AND remote_id=?", values: [kind, id])
        }
    }

    public func clearMessages(kind: String, id: Int) async throws {
        try database.transaction { db in
            try db.execute("DELETE FROM messages WHERE kind=? AND conversation_id=?", values: [kind, id])
            try db.execute("DELETE FROM drafts WHERE kind=? AND conversation_id=?", values: [kind, id])
            try db.execute("DELETE FROM card_states WHERE kind=? AND conversation_id=?", values: [kind, id])
            try db.execute("DELETE FROM sync_staging WHERE kind=? AND conversation_id=?", values: [kind, id])
            try db.execute("DELETE FROM sync_state WHERE kind=? AND conversation_id=?", values: [kind, id])
        }
    }
}
