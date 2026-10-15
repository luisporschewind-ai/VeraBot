import Foundation
import VeraBotCore
import VeraBotNetworking
import VeraBotPersistence

public actor LibraryRepository {
    public let store: LibraryStore
    public let api: any LibraryAPI
    private let sessionIsCurrent: @Sendable () -> Bool
    private var synchronizing = false
    public init(store: LibraryStore, api: any LibraryAPI, sessionIsCurrent: @escaping @Sendable () -> Bool = { true }) {
        self.store=store;self.api=api;self.sessionIsCurrent=sessionIsCurrent
    }
    public func cachedItems() throws -> [LibraryItem] { guard sessionIsCurrent() else { throw CancellationError() };return try store.items() }
    public func synchronize() async throws {
        guard !synchronizing else { return }
        synchronizing=true;defer { synchronizing=false }
        for attempt in 0..<3 {
            do {
                var items: [LibraryItem] = [], cursor: String?, revision: Int?
                var visited = Set<String>()
                repeat {
                    let page = try await api.libraryPage(cursor: cursor)
                    guard sessionIsCurrent(), !Task.isCancelled else { throw CancellationError() }
                    if let revision, page.snapshotRevision != revision { throw APIError(status:409,message:"资料已更新",code:"library_revision_changed") }
                    revision=page.snapshotRevision;items += page.items;cursor=page.nextCursor
                    if let cursor, !visited.insert(cursor).inserted { throw URLError(.badServerResponse) }
                } while cursor != nil
                guard sessionIsCurrent() else { throw CancellationError() }
                try store.replace(items:items,revision:revision ?? 0);return
            } catch let error as APIError where error.code == "library_revision_changed" && attempt < 2 { continue }
        }
    }
    public func search(query: String, botID: Int?) async throws -> [LibraryItem] { try await api.librarySearch(query:query,botID:botID) }
    public func link(id: String, botID: Int) async throws { try await api.libraryLink(id:id,botID:botID);try await synchronize() }
    public func unlink(id: String, botID: Int) async throws { try await api.libraryUnlink(id:id,botID:botID);try await synchronize() }
    public func delete(id: String) async throws {
        try await api.libraryDelete(id:id)
        guard sessionIsCurrent() else { throw CancellationError() }
        try store.remove(id:id)
    }
    public func upload(data: Data, filename: String, mime: String, botID: Int?, requestKey: String) async throws -> LibraryItem {
        let item=try await api.libraryUpload(data:data,filename:filename,mime:mime,botID:botID,requestKey:requestKey)
        try await synchronize();return item
    }
}
