import Foundation
import Testing
import VeraBotCore
import VeraBotNetworking
import VeraBotPersistence
import VeraBotData

func libraryFixture(_ id: String = "att_one", kind: String = "file", bots: [Int] = []) -> LibraryItem {
    LibraryItem(id: id, kind: kind, name: "report.txt", mime: "text/plain", bytes: 3,
                sha256: "abc", resourceVersion: "abc", createdAt: "2026-10-15", revision: 1,
                availability: "available", textStatus: "ready", botIDs: bots, sources: [])
}
actor LibraryFixtureAPI: LibraryAPI {
    var pages: [LibraryPage]
    var failAfterFirst: Bool
    init(pages: [LibraryPage], failAfterFirst: Bool = false) { self.pages = pages; self.failAfterFirst = failAfterFirst }
    func libraryPage(cursor: String?) async throws -> LibraryPage {
        if cursor != nil && failAfterFirst { throw URLError(.notConnectedToInternet) }
        return pages[cursor == nil ? 0 : 1]
    }
}
@Test func failedSecondLibraryPagePreservesPreviousSnapshot() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let db = LocalDatabase(url: root.appendingPathComponent("conversation.sqlite")); defer { db.close() }
    let store = LibraryStore(database: db)
    try store.replace(items: [libraryFixture("old")], revision: 1)
    let api = LibraryFixtureAPI(pages: [.init(items: [libraryFixture("new")], nextCursor: "page2", snapshotRevision: 2)], failAfterFirst: true)
    let repo = LibraryRepository(store: store, api: api)
    await #expect(throws: URLError.self) { try await repo.synchronize() }
    let items = try await repo.cachedItems()
    #expect(items.map(\.id) == ["old"])
}
@Test func completeLibrarySnapshotReplacesAtomicallyAndKeepsDraft() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let db = LocalDatabase(url: root.appendingPathComponent("conversation.sqlite")); defer { db.close() }
    try db.open()
    try db.execute("INSERT INTO drafts(kind,conversation_id,text,updated_at) VALUES('private',1,'keep',0)")
    let store = LibraryStore(database: db)
    let api = LibraryFixtureAPI(pages: [.init(items: [libraryFixture("first")], nextCursor: "page2", snapshotRevision: 2),.init(items: [libraryFixture("second")], nextCursor: nil, snapshotRevision: 2)])
    let repo = LibraryRepository(store: store, api: api)
    try await repo.synchronize()
    let items = try await repo.cachedItems()
    #expect(Set(items.map(\.id)) == ["first","second"])
    #expect(try db.rows("SELECT text FROM drafts").first?["text"] as? String == "keep")
}

@Test @MainActor func libraryTabsRespectScopeAndDeleteFailureKeepsItem() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let db=LocalDatabase(url:root.appendingPathComponent("test.sqlite"));defer { db.close() }
    let store=LibraryStore(database:db)
    let list=[libraryFixture("unlinked"),libraryFixture("image",kind:"image",bots:[1]),libraryFixture("document",bots:[1])]
    try store.replace(items:list,revision:1)
    let api=LibraryFixtureAPI(pages:[.init(items:list,nextCursor:nil,snapshotRevision:1)])
    let repo=LibraryRepository(store:store,api:api)
    let vm=LibraryViewModel(repository:repo,scope:.bot(id:1))
    await vm.load()
    #expect(vm.visibleItems(kind:"file",query:"").map(\.id) == ["document"])
    #expect(vm.visibleItems(kind:"image",query:"").map(\.id) == ["image"])
    await vm.delete(item:libraryFixture("document",bots:[1]))
    #expect(vm.items.contains { $0.id == "document" })
    #expect(vm.error != nil)
}
