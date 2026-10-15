import Foundation
import Observation
import VeraBotCore

@MainActor @Observable public final class LibraryViewModel {
    public private(set) var items: [LibraryItem] = []
    public private(set) var error: String?
    public private(set) var loading = false
    public private(set) var directorySynced = false
    public let scope: LibraryScope
    public let repository: LibraryRepository
    public init(repository: LibraryRepository, scope: LibraryScope) { self.repository=repository;self.scope=scope }
    public func load() async {
        if let cached=try? await repository.cachedItems() { items=cached }
        loading=true;defer { loading=false }
        do { try await repository.synchronize();items=try await repository.cachedItems();directorySynced=true;error=nil }
        catch is CancellationError { return }
        catch { self.error=error.localizedDescription }
    }
    public func visibleItems(kind: String, query: String) -> [LibraryItem] {
        items.filter { item in
            let linked: Bool
            switch scope { case .all: linked=true;case .bot(let id):linked=item.botIDs.contains(id) }
            return linked && item.kind==kind && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
    }
    public func search(query: String) async -> [LibraryItem]? {
        let botID: Int?;switch scope { case .all:botID=nil;case .bot(let id):botID=id }
        do { return try await repository.search(query:query,botID:botID) }
        catch { self.error="当前显示本地名称搜索结果；正文搜索需要联网";return nil }
    }
    public func delete(item: LibraryItem) async {
        do { try await repository.delete(id:item.id);items=try await repository.cachedItems();error=nil }
        catch { self.error=error.localizedDescription }
    }
    public func unlink(item: LibraryItem, botID: Int) async {
        do { try await repository.unlink(id:item.id,botID:botID);items=try await repository.cachedItems();error=nil }
        catch { self.error=error.localizedDescription }
    }
    public func link(item: LibraryItem, botID: Int) async throws {
        try await repository.link(id:item.id,botID:botID);items=try await repository.cachedItems()
    }
}
