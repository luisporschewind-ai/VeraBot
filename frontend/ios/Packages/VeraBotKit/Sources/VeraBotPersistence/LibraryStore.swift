import Foundation
import VeraBotCore

/// Uses the existing account database. Entire catalog snapshots commit atomically.
public final class LibraryStore: @unchecked Sendable {
    public let database: LocalDatabase
    public init(database: LocalDatabase) { self.database=database }
    public func items() throws -> [LibraryItem] {
        try database.rows("SELECT snapshot FROM library_items ORDER BY created_at DESC,id DESC").compactMap {
            guard let data = $0["snapshot"] as? Data else { return nil }
            return try JSONDecoder().decode(LibraryItem.self,from:data)
        }
    }
    public func replace(items: [LibraryItem], revision: Int) throws {
        let encoded = try items.map { ($0, try JSONEncoder().encode($0)) }
        try database.transaction { db in
            try db.execute("DELETE FROM library_items")
            for (item,data) in encoded {
                try db.execute("INSERT INTO library_items(id,created_at,snapshot) VALUES (?,?,?)",values:[item.id,item.createdAt,data])
            }
            try db.execute("INSERT OR REPLACE INTO library_state(key,value) VALUES ('revision',?)",values:[String(revision)])
        }
    }
    public func remove(id: String) throws { try database.execute("DELETE FROM library_items WHERE id=?",values:[id]) }
    public func value(key: String) throws -> String? { try database.rows("SELECT value FROM library_state WHERE key=?",values:[key]).first?["value"] as? String }
    public func set(key: String, value: String) throws { try database.execute("INSERT OR REPLACE INTO library_state(key,value) VALUES (?,?)",values:[key,value]) }
}
