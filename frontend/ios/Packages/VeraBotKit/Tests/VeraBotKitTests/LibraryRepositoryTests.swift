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

private actor PausedLibraryAPI: LibraryAPI {
    var calls=0
    var continuation: CheckedContinuation<Void,Never>?
    var secondCompleted=false
    func libraryPage(cursor:String?) async throws -> LibraryPage {
        calls += 1
        await withCheckedContinuation { continuation=$0 }
        return .init(items:[libraryFixture()],nextCursor:nil,snapshotRevision:1)
    }
    func release() { continuation?.resume();continuation=nil }
    func markCompleted() { secondCompleted=true }
}
@Test func concurrentLibrarySynchronizationWaitsForCommittedSnapshot() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:root)}
    let db=LocalDatabase(url:root.appendingPathComponent("test.sqlite"));defer {db.close()}
    let api=PausedLibraryAPI(), repo=LibraryRepository(store:LibraryStore(database:db),api:api)
    let first=Task {try await repo.synchronize()}
    while await api.calls==0 {await Task.yield()}
    let second=Task {try await repo.synchronize();await api.markCompleted()}
    try await Task.sleep(for:.milliseconds(30))
    #expect(await api.secondCompleted == false)
    await api.release();try await first.value;try await second.value
    #expect(try await repo.cachedItems().count==1)
}

@Test @MainActor func groupLibraryUsesMessageSourcesRatherThanMemberBotLinks() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = LocalDatabase(url: root.appendingPathComponent("group.sqlite"))
    defer { database.close() }
    func item(_ id: String, kind: String = "file", group: Int?, available: Bool = true) throws -> LibraryItem {
        let source = try JSONDecoder().decode(LibrarySource.self, from: Data("""
        {"kind":"\(group == nil ? "private" : "group")","source_id":\(group ?? 99),"bot_id":1,"display_name":"source","message_id":7,"created_at":"2026-10-16","message_available":\(available)}
        """.utf8))
        return LibraryItem(id:id,kind:kind,name:"report",mime:"text/plain",bytes:3,sha256:"abc",resourceVersion:"abc",createdAt:"2026-10-16",revision:1,availability:"available",textStatus:"ready",botIDs:[1],sources:[source])
    }
    let items = try [item("own-file", group:7), item("own-image", kind:"image", group:7),
                     item("cleared-source", group:7, available:false), item("other-group", group:8), item("private", group:nil)]
    let store = LibraryStore(database:database)
    try store.replace(items:items, revision:1)
    let api = GroupLibraryFixtureAPI(items:items)
    let vm = LibraryViewModel(repository:LibraryRepository(store:store,api:api),scope:.group(id:7))
    await vm.load()
    #expect(Set(vm.visibleItems(kind:"file",query:"").map(\.id)) == ["own-file","cleared-source"])
    #expect(vm.visibleItems(kind:"image",query:"").map(\.id) == ["own-image"])
    #expect(Set(try #require(await vm.search(query:"report")).map(\.id)) == ["own-file","own-image","cleared-source"])
}
private actor GroupLibraryFixtureAPI: LibraryAPI {
    let items: [LibraryItem]
    init(items: [LibraryItem]) { self.items=items }
    func libraryPage(cursor: String?) async throws -> LibraryPage { .init(items:items,nextCursor:nil,snapshotRevision:1) }
    func librarySearch(query: String, botID: Int?) async throws -> [LibraryItem] { items }
}
