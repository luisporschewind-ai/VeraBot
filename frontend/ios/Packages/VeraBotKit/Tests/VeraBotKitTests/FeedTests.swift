import Foundation
import Testing
import VeraBotCore
import VeraBotData
@testable import VeraBotNetworking

// Removing snake-case/null decoding, sparse state writes, or request filters breaks these contract tests.
@Test func feedDecodesNullablePayloadAndIndependentState() throws {
    let item = try JSONDecoder().decode(FeedItem.self, from: Data(#"{"id":9,"kind":"audio","title":"Actual title","url":"https://example.com/a","author":null,"source_id":1,"source_name":"Example","bot_id":null,"bot_name":null,"published_at":null,"created_at":"2026-10-17T00:00:00+00:00","summary":"Actual source description","summary_basis":"description","recommendation_reason":"subscription","image_url":null,"media_url":null,"duration_seconds":null,"read":false,"saved":true,"dismissed":false,"recommended_by":[{"bot_id":7,"bot_name":"Bot","reason":"subscription"}]}"#.utf8))
    #expect(item.id == 9 && item.saved && !item.read)
    #expect(item.author == nil && item.mediaURL == nil && item.durationSeconds == nil)
    #expect(item.recommendedBy.first?.botID == 7)
    #expect(item.evidenceLabel == "来源简介")
    let source = try JSONDecoder().decode(FeedSource.self, from: Data(#"{"id":1,"name":"Example","url":"https://example.com/feed","kind":"news","bot_id":null,"enabled":true,"last_success_at":null,"next_fetch_at":null,"last_error":null,"failure_count":0}"#.utf8))
    #expect(source.nextFetchAt == nil && source.failureCount == 0)
    let data = try JSONEncoder().encode(FeedItemState(saved: false))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json.keys.sorted() == ["saved"])
    #expect(json["saved"] as? Bool == false)
}

@Test func feedRequestsUseAuthenticatedTransportFiltersAndMemoryOverride() async throws {
    let sessionConfig = URLSessionConfiguration.ephemeral
    sessionConfig.protocolClasses = [FeedContractProtocol.self]
    let session = URLSession(configuration: sessionConfig)
    defer { session.invalidateAndCancel() }
    let api = APIClient(baseURL: URL(string: "https://feed-contract.test")!, token: "access", urlSession: session)
    let page = try await api.feedItems(query: FeedQuery(kind: "audio", botID: 7, savedOnly: true), cursor: "19")
    #expect(page.items.isEmpty && page.nextCursor == "18")
    let suggested = try await api.feedSuggest(botIDs: [7], topics: ["Swift"], useMemory: false)
    #expect(suggested.basis == "memory off")
    let plan = try await api.feedSavePlan(FeedPlanUpdate(enabled: true, botIDs: [7], topics: ["Swift"], excludedTopics: [], useMemory: false, expectedVersion: 4))
    #expect(!plan.useMemory && plan.version == 5)
    let updated = try await api.feedSetState(id: 9, state: FeedItemState(read: true))
    #expect(updated.read && !updated.saved)
    let context = try await api.feedContext(id: 9, botID: 7)
    #expect(context.botID == 7 && context.prompt == "bounded source")
    let first = try await api.feedItems(query: FeedQuery(), cursor: nil)
    #expect(first.nextCursor == nil)
}

private final class FeedContractProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "feed-contract.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let bytes: Data?
        if let data = request.httpBody { bytes = data }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
            bytes = data
        } else { bytes = nil }
        let body = bytes.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var valid = request.value(forHTTPHeaderField: "Authorization") == "Bearer access"
        var response = "{}"
        switch components.path {
        case "/api/feed/items":
            if params["cursor"] != nil {
                valid = valid && params == ["kind":"audio", "bot_id":"7", "saved_only":"true", "cursor":"19", "limit":"20"]
                response = #"{"items":[],"next_cursor":"18"}"#
            } else {
                valid = valid && params == ["saved_only":"false", "limit":"20"]
                response = #"{"items":[],"next_cursor":null}"#
            }
        case "/api/feed/plan/suggest":
            valid = valid && request.httpMethod == "POST" && body["use_memory"] as? Bool == false && body["bot_ids"] as? [Int] == [7] && body["topics"] as? [String] == ["Swift"]
            response = #"{"topics":[],"sources":[],"basis":"memory off"}"#
        case "/api/feed/plan":
            valid = valid && request.httpMethod == "PUT" && body["expected_version"] as? Int == 4 && body["use_memory"] as? Bool == false && body["daily_limit"] == nil
            response = #"{"enabled":true,"bot_ids":[7],"topics":["Swift"],"excluded_topics":[],"use_memory":false,"daily_limit":20,"version":5}"#
        case "/api/feed/items/9/state":
            valid = valid && request.httpMethod == "PATCH" && body.keys.sorted() == ["read"] && body["read"] as? Bool == true
            response = String(data: try! JSONEncoder().encode(FeedItem(id: 9, read: true)), encoding: .utf8)!
        case "/api/feed/items/9/context":
            valid = valid && params == ["bot_id":"7"]
            response = #"{"bot_id":7,"prompt":"bounded source"}"#
        default: valid = false
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 422, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((valid ? response : #"{"detail":"request contract mismatch"}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// Only network completion is controlled: all list merging, error preservation and identity fences are real VM behavior.
private actor FeedStub: FeedAPI {
    var pages: [FeedPage] = []
    var failing = false
    var setupFails = false
    var storedPlan = FeedPlan(enabled: true, botIDs: [7], topics: ["before"], version: 4)
    var storedSources = [FeedSource(id: 1, name: "Existing", url: "https://example.com/rss", enabled: true)]
    var setupWaiter: CheckedContinuation<[FeedCatalogSource], Error>?
    var delayCatalog = false
    var metadataReads = 0
    func delaySetup() { delayCatalog = true; metadataReads = 0 }
    func capturedSetup() -> Bool { setupWaiter != nil && metadataReads >= 2 }
    func finishSetup() { setupWaiter?.resume(returning: []); setupWaiter = nil }
    var suspended: CheckedContinuation<FeedPage, Error>?
    var suspendNext = false
    var savedMemoryEnabled = true
    var stateWaiter: CheckedContinuation<FeedItem, Error>?
    var contextWaiter: CheckedContinuation<FeedContext, Error>?
    var delayState = false
    var delayContext = false
    func memory(_ enabled: Bool) { savedMemoryEnabled = enabled }
    func delayFeedback() { delayState = true }
    func delayDraft() { delayContext = true }
    func waitingFeedback() -> Bool { stateWaiter != nil }
    func waitingDraft() -> Bool { contextWaiter != nil }
    func finishFeedback() { stateWaiter?.resume(returning: FeedItem(id: 9, saved: true)); stateWaiter = nil }
    func finishDraft() { contextWaiter?.resume(returning: FeedContext(botID: 7, prompt: "old account context")); contextWaiter = nil }
    func enqueue(_ pages: [FeedPage]) { self.pages = pages }
    func fail(_ value: Bool) { failing = value }
    func failSetup() { setupFails = true }
    func suspend() { suspendNext = true }
    func hasSuspended() -> Bool { suspended != nil }
    func resume(_ page: FeedPage) { suspended?.resume(returning: page); suspended = nil }
    func feedItems(query: FeedQuery, cursor: String?) async throws -> FeedPage {
        if suspendNext { suspendNext = false; return try await withCheckedThrowingContinuation { suspended = $0 } }
        if failing { throw APIError(status: 503, message: "offline") }
        return pages.isEmpty ? FeedPage(items: [], nextCursor: nil) : pages.removeFirst()
    }
    func feedPlan() async throws -> FeedPlan {
        if setupFails { throw APIError(status: 503, message: "setup offline") }
        metadataReads += 1
        var plan = storedPlan; plan.useMemory = savedMemoryEnabled
        return plan
    }
    func feedSuggest(botIDs: [Int], topics: [String], useMemory: Bool) async throws -> FeedSuggestion {
        FeedSuggestion(basis: useMemory ? "memory used" : "memory off")
    }
    func feedContext(id: Int, botID: Int) async throws -> FeedContext {
        if delayContext { delayContext = false; return try await withCheckedThrowingContinuation { contextWaiter = $0 } }
        return FeedContext(botID: botID, prompt: "bounded source")
    }
    func feedSources() async throws -> [FeedSource] { metadataReads += 1; return storedSources }
    func feedCatalog() async throws -> [FeedCatalogSource] {
        if delayCatalog { delayCatalog = false; return try await withCheckedThrowingContinuation { setupWaiter = $0 } }
        return []
    }
    func feedSetSource(id: Int, enabled: Bool) async throws -> FeedSource {
        let index = storedSources.firstIndex(where: { $0.id == id })!
        storedSources[index].enabled = enabled
        return storedSources[index]
    }
    func feedAddSource(_ create: FeedSourceCreate) async throws -> FeedSource {
        let value = FeedSource(id: 2, name: create.name, url: create.url, kind: create.kind, botID: create.botID)
        storedSources.append(value); return value
    }
    func feedSavePlan(_ update: FeedPlanUpdate) async throws -> FeedPlan {
        guard update.expectedVersion == storedPlan.version else { throw APIError(status: 409, message: "conflict") }
        savedMemoryEnabled = update.useMemory
        storedPlan = FeedPlan(enabled: update.enabled, botIDs: update.botIDs, topics: update.topics, excludedTopics: update.excludedTopics, useMemory: update.useMemory, version: storedPlan.version + 1)
        return storedPlan
    }
    func feedSetState(id: Int, state: FeedItemState) async throws -> FeedItem {
        if delayState { delayState = false; return try await withCheckedThrowingContinuation { stateWaiter = $0 } }
        if failing { throw APIError(status: 500, message: "feedback failed") }
        return FeedItem(id: id, read: state.read ?? false, saved: state.saved ?? false, dismissed: state.dismissed ?? false)
    }
}

@MainActor @Test func feedPaginationDeduplicatesAndRefreshFailureKeepsContent() async {
    let api = FeedStub()
    await api.enqueue([FeedPage(items: [FeedItem(id: 9), FeedItem(id: 8)], nextCursor: "8"), FeedPage(items: [FeedItem(id: 8), FeedItem(id: 7)], nextCursor: nil)])
    let vm = FeedViewModel(api: api, identity: "account-a")
    await vm.reloadItems()
    await vm.loadMore()
    #expect(vm.items.map(\.id) == [9, 8, 7] && vm.nextCursor == nil)
    await api.fail(true)
    await vm.reloadItems()
    #expect(vm.items.map(\.id) == [9, 8, 7] && vm.error == "offline")
    let updated = await vm.setState(id: 9, state: FeedItemState(saved: true))
    #expect(updated == nil && vm.items.first?.saved == false && vm.error == "feedback failed")
}

@MainActor @Test func feedAccountAndFilterChangesDiscardLateResponsesAndContext() async {
    let api = FeedStub()
    let vm = FeedViewModel(api: api, identity: "account-a")
    await api.suspend()
    let old = Task { await vm.reloadItems() }
    while !(await api.hasSuspended()) { await Task.yield() }
    vm.configure(api: api, identity: "account-b")
    await api.resume(FeedPage(items: [FeedItem(id: 111)], nextCursor: "111"))
    await old.value
    #expect(vm.items.isEmpty && vm.nextCursor == nil && !vm.loading)
    await api.suspend()
    let oldFilter = Task { await vm.reloadItems() }
    while !(await api.hasSuspended()) { await Task.yield() }
    await vm.apply(query: FeedQuery(savedOnly: true))
    await api.resume(FeedPage(items: [FeedItem(id: 222)], nextCursor: nil))
    await oldFilter.value
    #expect(vm.items.isEmpty && vm.query.savedOnly)
}

@MainActor @Test func feedCancellationNeverReplacesVisibleItems() async {
    let api = FeedStub()
    await api.enqueue([FeedPage(items: [FeedItem(id: 7)], nextCursor: nil)])
    let vm = FeedViewModel(api: api, identity: "account-a")
    await vm.reloadItems()
    await api.suspend()
    let load = Task { await vm.reloadItems() }
    while !(await api.hasSuspended()) { await Task.yield() }
    load.cancel()
    await api.resume(FeedPage(items: [FeedItem(id: 999)], nextCursor: nil))
    await load.value
    #expect(vm.items.map(\.id) == [7] && vm.error == nil && !vm.loading)
}

@Test func feedDraftCombinesContextWithoutOverwritingSavedDraft() {
    #expect(FeedChatDraft.merging(existing: "my unfinished question", incoming: "source context") == "my unfinished question\n\nsource context")
    #expect(FeedChatDraft.merging(existing: "", incoming: "source context") == "source context")
    #expect(FeedChatDraft.merging(existing: "keep", incoming: nil) == "keep")
}

@Test func feedPrivateChatCountsAsVisibleOnlyInConversationTabs() {
    #expect(ConversationVisibilityPolicy.allowsConversation(selectedTab: 0, isGroup: false))
    #expect(ConversationVisibilityPolicy.allowsConversation(selectedTab: 5, isGroup: false))
    #expect(!ConversationVisibilityPolicy.allowsConversation(selectedTab: 5, isGroup: true))
    for tab in [1, 2, 3, 4] { #expect(!ConversationVisibilityPolicy.allowsConversation(selectedTab: tab, isGroup: false)) }
}

@MainActor @Test func feedIdentityFencesLateFeedbackAndAskBotContext() async {
    let api = FeedStub()
    let vm = FeedViewModel(api: api, identity: "account-a")
    await api.delayFeedback()
    let feedback = Task { await vm.setState(id: 9, state: FeedItemState(saved: true)) }
    while !(await api.waitingFeedback()) { await Task.yield() }
    vm.configure(api: api, identity: "account-b")
    await api.finishFeedback()
    #expect(await feedback.value == nil)
    #expect(vm.details.isEmpty && vm.items.isEmpty && !vm.busy)
    await api.delayDraft()
    let draft = Task { await vm.context(id: 9, botID: 7, allowedBotIDs: [7]) }
    while !(await api.waitingDraft()) { await Task.yield() }
    vm.configure(api: api, identity: "server-c")
    await api.finishDraft()
    #expect(await draft.value == nil)
    #expect(!vm.busy)
    #expect(await vm.context(id: 9, botID: 123, allowedBotIDs: [7]) == nil)
}

@MainActor @Test func feedSuggestionCannotOverridePersistedMemoryOff() async {
    let api = FeedStub()
    await api.memory(false)
    let vm = FeedViewModel(api: api, identity: "account-a")
    await vm.loadSetup()
    #expect(vm.plan.useMemory == false)
    #expect(await vm.suggest(botIDs: [7], topics: [], useMemory: true)?.basis == "memory off")
}

@MainActor @Test func feedSetupFailureRemainsVisibleAfterSuccessfulListLoad() async {
    let api = FeedStub()
    await api.failSetup()
    let vm = FeedViewModel(api: api, identity: "account-a")
    await vm.loadSetup()
    await vm.reloadItems()
    #expect(vm.setupError == "setup offline" && !vm.setupLoaded)
}


@MainActor @Test(arguments: ["pause", "add", "save"])
func feedLateSetupCannotUndoAcknowledgedMetadataWrite(operation: String) async {
    let api = FeedStub()
    let vm = FeedViewModel(api: api, identity: "account-a")
    await vm.loadSetup()
    await api.delaySetup()
    let setup = Task { await vm.loadSetup() }
    while !(await api.capturedSetup()) { await Task.yield() }
    switch operation {
    case "pause":
        await vm.setSource(id: 1, enabled: false)
        #expect(vm.sources.first?.enabled == false)
    case "add":
        #expect(await vm.addSource(FeedSourceCreate(name: "Added", url: "https://example.org/rss", kind: "audio")))
        #expect(vm.sources.map(\.id) == [1, 2])
    default:
        #expect(await vm.savePlan(FeedPlanUpdate(enabled: false, botIDs: [7], topics: ["after"], excludedTopics: [], useMemory: false, expectedVersion: 4)))
        #expect(vm.plan.version == 5 && vm.plan.topics == ["after"])
    }
    await api.finishSetup()
    await setup.value
    switch operation {
    case "pause": #expect(vm.sources.first?.enabled == false)
    case "add": #expect(vm.sources.map(\.id) == [1, 2])
    default: #expect(vm.plan.version == 5 && vm.plan.topics == ["after"] && !vm.plan.enabled)
    }
    #expect(vm.setupLoaded && !vm.loadingSetup)
}

@MainActor @Test func feedSuccessfulListDoesNotHideConcurrentFeedbackFailure() async {
    let api = FeedStub()
    await api.enqueue([FeedPage(items: [FeedItem(id: 9)], nextCursor: nil)])
    let vm = FeedViewModel(api: api, identity: "account-a")
    await vm.reloadItems()
    await api.suspend()
    let load = Task { await vm.reloadItems() }
    while !(await api.hasSuspended()) { await Task.yield() }
    await api.fail(true)
    #expect(await vm.setState(id: 9, state: FeedItemState(saved: true)) == nil)
    #expect(vm.error == "feedback failed")
    await api.resume(FeedPage(items: [FeedItem(id: 9)], nextCursor: nil))
    await load.value
    #expect(vm.error == "feedback failed")
    #expect(vm.items.first?.saved == false)
}

@MainActor @Test func feedCancelledAskBotDoesNotReturnLateContext() async {
    let api = FeedStub()
    let vm = FeedViewModel(api: api, identity: "account-a")
    await api.delayDraft()
    let handoff = Task { await vm.context(id: 9, botID: 7, allowedBotIDs: [7]) }
    while !(await api.waitingDraft()) { await Task.yield() }
    handoff.cancel()
    await api.finishDraft()
    #expect(await handoff.value == nil)
    #expect(!vm.busy && vm.error == nil)
}

@MainActor @Test func feedPlanEditorWaitsForPersistedPlanInsteadOfUsingDefaults() async throws {
    let api = FeedStub()
    let vm = FeedViewModel(api: api, identity: "account-a")
    #expect(vm.editablePlan == nil)
    await api.delaySetup()
    let setup = Task { await vm.loadSetup() }
    while !(await api.capturedSetup()) { await Task.yield() }
    #expect(vm.editablePlan == nil)
    await api.finishSetup()
    await setup.value
    let initial = try #require(vm.editablePlan)
    #expect(initial.enabled && initial.version == 4)
    #expect(initial.botIDs == [7] && initial.topics == ["before"])
}
