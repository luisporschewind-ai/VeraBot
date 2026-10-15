import Foundation

public struct LibrarySource: Codable, Sendable, Hashable {
    public let kind: String
    public let sourceID: Int?
    public let botID: Int?
    public let displayName: String
    public let messageID: Int?
    public let createdAt: String
    public let messageAvailable: Bool
    enum CodingKeys: String, CodingKey {
        case kind, sourceID = "source_id", botID = "bot_id", displayName = "display_name"
        case messageID = "message_id", createdAt = "created_at", messageAvailable = "message_available"
    }
}
public struct LibraryItem: Codable, Sendable, Hashable, Identifiable {
    public let id, kind, name, mime: String
    public let bytes: Int
    public let sha256, resourceVersion, createdAt: String
    public let revision: Int
    public let availability: String
    public let textStatus: String?
    public let botIDs: [Int]
    public let sources: [LibrarySource]
    public init(id: String, kind: String, name: String, mime: String, bytes: Int, sha256: String, resourceVersion: String,
                createdAt: String, revision: Int, availability: String, textStatus: String?, botIDs: [Int], sources: [LibrarySource]) {
        self.id=id; self.kind=kind; self.name=name; self.mime=mime; self.bytes=bytes; self.sha256=sha256
        self.resourceVersion=resourceVersion; self.createdAt=createdAt; self.revision=revision; self.availability=availability
        self.textStatus=textStatus; self.botIDs=botIDs; self.sources=sources
    }
    public var isImage: Bool { kind == "image" }
    enum CodingKeys: String, CodingKey {
        case id,kind,name,mime,bytes,sha256,revision,availability,sources
        case resourceVersion = "resource_version", createdAt = "created_at", textStatus = "text_status", botIDs = "bot_ids"
    }
}
public struct LibraryPage: Codable, Sendable {
    public let items: [LibraryItem]
    public let nextCursor: String?
    public let snapshotRevision: Int
    public init(items: [LibraryItem], nextCursor: String?, snapshotRevision: Int) {
        self.items=items;self.nextCursor=nextCursor;self.snapshotRevision=snapshotRevision
    }
    enum CodingKeys: String, CodingKey { case items, nextCursor = "next_cursor", snapshotRevision = "snapshot_revision" }
}
public enum LibraryScope: Hashable, Sendable { case all; case bot(id: Int) }
public enum LibraryDownloadMode: String, Codable, Sendable { case automaticWiFi, manualCellularAllowed }
