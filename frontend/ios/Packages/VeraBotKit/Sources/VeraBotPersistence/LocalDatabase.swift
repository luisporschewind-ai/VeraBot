import Foundation
import CSQLite

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum PersistenceError: Error, LocalizedError {
    case sqlite(String)
    case encoding
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): "本地数据保存失败：\(message)"
        case .encoding: "本地数据编码失败"
        case .invalidJSON: "本地数据格式无法读取"
        }
    }
}

public struct SQLiteValues: @unchecked Sendable, ExpressibleByArrayLiteral {
    fileprivate let values: [Any?]
    public init(arrayLiteral elements: Any?...) { values = elements }
    public init(_ values: [Any?]) { self.values = values }
}

public struct SQLiteRow: @unchecked Sendable {
    fileprivate let values: [String: Any]
    public subscript(_ key: String) -> Any? { values[key] }
}

/// A serialized SQLite connection. All statements bind user values; schema changes are transactional.
public final class LocalDatabase: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var handle: OpaquePointer?
    private var invalidated = false
    public let url: URL

    public init(url: URL) { self.url = url }

    public func open() throws {
        lock.lock(); defer { lock.unlock() }
        guard !invalidated else { throw PersistenceError.sqlite("database scope is closed") }
        guard handle == nil else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw failure
        }
        sqlite3_busy_timeout(handle, 5000)
        try exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL;")
        try migrate()
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        invalidated = true
        guard let handle else { return }
        sqlite3_close_v2(handle)
        self.handle = nil
    }

    public func execute(_ sql: String, values: SQLiteValues = []) throws {
        lock.lock(); defer { lock.unlock() }
        if handle == nil { try open() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values.values, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw failure }
    }

    public func rows(_ sql: String, values: SQLiteValues = []) throws -> [SQLiteRow] {
        lock.lock(); defer { lock.unlock() }
        if handle == nil { try open() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values.values, to: statement)
        var result: [SQLiteRow] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw failure }
            var row: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT:
                    if let raw = sqlite3_column_text(statement, index) { row[name] = String(cString: raw) }
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, index))
                    if let raw = sqlite3_column_blob(statement, index) { row[name] = Data(bytes: raw, count: count) }
                default: row[name] = NSNull()
                }
            }
            result.append(SQLiteRow(values: row))
        }
        return result
    }

    public func transaction<T>(_ body: (LocalDatabase) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        if handle == nil { try open() }
        try exec("BEGIN IMMEDIATE")
        do {
            let value = try body(self)
            try exec("COMMIT")
            return value
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func migrate() throws {
        let version = try rows("PRAGMA user_version").first?["user_version"] as? Int ?? 0
        guard version < 1 else { return }
        try exec("BEGIN IMMEDIATE")
        do {
            try exec("""
                CREATE TABLE conversations(
                    kind TEXT NOT NULL, remote_id INTEGER NOT NULL, snapshot BLOB NOT NULL,
                    updated_at REAL NOT NULL, PRIMARY KEY(kind, remote_id));
                CREATE TABLE messages(
                    local_id TEXT PRIMARY KEY, kind TEXT NOT NULL, conversation_id INTEGER NOT NULL,
                    remote_id INTEGER, sort_key INTEGER NOT NULL, snapshot BLOB NOT NULL,
                    local_status TEXT NOT NULL DEFAULT 'synced',
                    UNIQUE(kind, conversation_id, remote_id));
                CREATE INDEX messages_order ON messages(kind, conversation_id, sort_key, local_id);
                CREATE TABLE drafts(kind TEXT NOT NULL, conversation_id INTEGER NOT NULL, text TEXT NOT NULL,
                    updated_at REAL NOT NULL, PRIMARY KEY(kind, conversation_id));
                CREATE TABLE card_states(kind TEXT NOT NULL, conversation_id INTEGER NOT NULL,
                    card_kind TEXT NOT NULL, remote_id INTEGER NOT NULL, snapshot BLOB NOT NULL,
                    PRIMARY KEY(kind, conversation_id, card_kind, remote_id));
                CREATE TABLE sync_state(kind TEXT NOT NULL, conversation_id INTEGER NOT NULL,
                    completed_revision INTEGER, active_revision INTEGER, next_before_id INTEGER,
                    complete INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY(kind, conversation_id));
                CREATE TABLE sync_staging(kind TEXT NOT NULL, conversation_id INTEGER NOT NULL,
                    revision INTEGER NOT NULL, remote_id INTEGER NOT NULL, snapshot BLOB NOT NULL,
                    PRIMARY KEY(kind, conversation_id, revision, remote_id));
                CREATE TABLE list_state(kind TEXT PRIMARY KEY, complete INTEGER NOT NULL DEFAULT 0);
                PRAGMA user_version=1;
                """)
            try exec("COMMIT")
        } catch { try? exec("ROLLBACK"); throw error }
    }

    private func exec(_ sql: String) throws {
        guard let handle else { throw PersistenceError.sqlite("database is closed") }
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &message)
        guard result == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(message)
            throw PersistenceError.sqlite(detail)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let handle else { throw PersistenceError.sqlite("database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure }
        return statement
    }

    private func bind(_ values: [Any?], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case nil, is NSNull: status = sqlite3_bind_null(statement, index)
            case let value as Int: status = sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Int64: status = sqlite3_bind_int64(statement, index, value)
            case let value as Double: status = sqlite3_bind_double(statement, index, value)
            case let value as String:
                status = value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
            case let value as Data:
                status = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), sqliteTransient) }
            default: throw PersistenceError.sqlite("unsupported SQL binding")
            }
            guard status == SQLITE_OK else { throw failure }
        }
    }

    private var failure: PersistenceError {
        .sqlite(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed")
    }
}
