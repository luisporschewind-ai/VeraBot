import Foundation
import Observation
import VeraBotCore
import VeraBotNetworking

@MainActor @Observable public final class FeedViewModel {
    public private(set) var items: [FeedItem] = []
    public private(set) var details: [Int: FeedItem] = [:]
    public private(set) var plan = FeedPlan()
    public private(set) var catalog: [FeedCatalogSource] = []
    public private(set) var sources: [FeedSource] = []
    public private(set) var query = FeedQuery()
    public private(set) var nextCursor: String?
    public private(set) var loading = false
    public private(set) var loadingSetup = false
    public private(set) var busy = false
    public private(set) var setupLoaded = false
    /// Form snapshots may only originate from successfully loaded persisted state.
    public var editablePlan: FeedPlan? { setupLoaded ? plan : nil }
    public private(set) var listError: String?
    public private(set) var mutationError: String?
    public var error: String? { mutationError ?? listError }
    public private(set) var setupError: String?
    public private(set) var notice: String?
    public private(set) var identity: String
    @ObservationIgnored private var api: any FeedAPI
    @ObservationIgnored private var scopeGeneration: UInt64 = 0
    @ObservationIgnored private var listGeneration: UInt64 = 0
    @ObservationIgnored private var metadataGeneration: UInt64 = 0

    public init(api: any FeedAPI, identity: String) { self.api = api; self.identity = identity }

    /// Account/server changes discard all state and fence loads, mutations and context handoffs.
    public func configure(api: any FeedAPI, identity: String) {
        guard self.identity != identity else { return }
        scopeGeneration &+= 1; listGeneration &+= 1
        self.api = api; self.identity = identity
        items = []; details = [:]; plan = FeedPlan(); sources = []; catalog = []; query = FeedQuery()
        nextCursor = nil; loading = false; loadingSetup = false; busy = false; setupLoaded = false; listError = nil; mutationError = nil; setupError = nil; notice = nil
    }

    public func load() async {
        async let setup: Void = loadSetup()
        await reloadItems()
        await setup
    }

    public func loadSetup() async {
        guard !loadingSetup else { return }
        let generation = scopeGeneration
        loadingSetup = true
        defer { if generation == scopeGeneration { loadingSetup = false } }
        // A write can finish while these independent reads are pending. Refetch the
        // metadata as a unit rather than replacing an acknowledged write with that older snapshot.
        while generation == scopeGeneration, !Task.isCancelled {
            let revision = metadataGeneration
            let requestAPI = api
            do {
                async let planValue = requestAPI.feedPlan()
                async let sourceValue = requestAPI.feedSources()
                async let catalogValue = requestAPI.feedCatalog()
                let result = try await (planValue, sourceValue, catalogValue)
                guard generation == scopeGeneration, !Task.isCancelled else { return }
                guard revision == metadataGeneration else { continue }
                plan = result.0; sources = result.1; catalog = result.2; setupLoaded = true; setupError = nil
                return
            } catch {
                guard generation == scopeGeneration, !Task.isCancelled, !(error is CancellationError) else { return }
                guard revision == metadataGeneration else { continue }
                setupError = error.localizedDescription
                return
            }
        }
    }

    public func apply(query: FeedQuery) async {
        guard self.query != query else { return }
        self.query = query
        items = []; nextCursor = nil
        await reloadItems()
    }

    public func reloadItems() async { await loadPage(append: false) }
    public func loadMore() async {
        guard !loading, nextCursor != nil else { return }
        await loadPage(append: true)
    }

    private func loadPage(append: Bool) async {
        let scope = scopeGeneration
        listGeneration &+= 1
        let generation = listGeneration
        let requestQuery = query
        let cursor = append ? nextCursor : nil
        loading = true
        defer { if scope == scopeGeneration, generation == listGeneration { loading = false } }
        do {
            let page = try await api.feedItems(query: requestQuery, cursor: cursor)
            guard scope == scopeGeneration, generation == listGeneration, !Task.isCancelled else { return }
            var seen = Set<Int>()
            items = ((append ? items : []) + page.items).filter { seen.insert($0.id).inserted }
            // A repeating cursor must not trap the user in an endless load-more loop.
            nextCursor = page.nextCursor == cursor ? nil : page.nextCursor
            listError = nil
        } catch {
            guard generation == listGeneration else { return }
            record(error, generation: scope, isList: true)
        }
    }

    public func savePlan(_ update: FeedPlanUpdate) async -> Bool {
        let generation = scopeGeneration
        guard let updated = await perform({ try await $0.feedSavePlan(update) }), generation == scopeGeneration, !Task.isCancelled else { return false }
        metadataGeneration &+= 1
        plan = updated
        await reloadItems()
        return true
    }

    public func suggest(botIDs: [Int], topics: [String], useMemory: Bool) async -> FeedSuggestion? {
        let allowed = useMemory && plan.useMemory
        return await perform { try await $0.feedSuggest(botIDs: botIDs, topics: topics, useMemory: allowed) }
    }

    public func addSource(_ create: FeedSourceCreate) async -> Bool {
        let generation = scopeGeneration
        guard let source = await perform({ try await $0.feedAddSource(create) }), generation == scopeGeneration, !Task.isCancelled else { return false }
        metadataGeneration &+= 1
        if let index = sources.firstIndex(where: { $0.id == source.id }) { sources[index] = source }
        else { sources.append(source) }
        return true
    }

    public func setSource(id: Int, enabled: Bool) async {
        let generation = scopeGeneration
        guard let source = await perform({ try await $0.feedSetSource(id: id, enabled: enabled) }), generation == scopeGeneration, !Task.isCancelled else { return }
        metadataGeneration &+= 1
        if let index = sources.firstIndex(where: { $0.id == id }) { sources[index] = source }
        await reloadItems()
    }

    public func refresh() async {
        let generation = scopeGeneration
        guard let queued = await perform({ try await $0.feedRefresh() }), generation == scopeGeneration, !Task.isCancelled else { return }
        notice = queued ? "已请求检查来源；后台采集完成后，再次刷新查看新内容。" : "关注计划已暂停。收藏仍可查看。"
        await reloadItems()
    }

    @discardableResult public func setState(id: Int, state: FeedItemState) async -> FeedItem? {
        let generation = scopeGeneration
        guard let updated = await perform({ try await $0.feedSetState(id: id, state: state) }), generation == scopeGeneration, !Task.isCancelled else { return nil }
        // Prevent an older list response from reverting newly acknowledged feedback.
        listGeneration &+= 1; loading = false
        details[id] = updated
        if updated.dismissed || (query.savedOnly && !updated.saved) { items.removeAll { $0.id == id } }
        else if let index = items.firstIndex(where: { $0.id == id }) { items[index] = updated }
        return updated
    }

    public func loadDetail(id: Int) async {
        let generation = scopeGeneration
        guard let item = await perform({ try await $0.feedItem(id: id) }), generation == scopeGeneration, !Task.isCancelled else { return }
        details[id] = item
        if !item.read { _ = await setState(id: id, state: FeedItemState(read: true)) }
    }

    public func context(id: Int, botID: Int, allowedBotIDs: Set<Int>) async -> FeedContext? {
        guard allowedBotIDs.contains(botID) else { mutationError = "请选择当前账号的 Bot"; return nil }
        let generation = scopeGeneration
        guard let value = await perform({ try await $0.feedContext(id: id, botID: botID) }), generation == scopeGeneration, !Task.isCancelled else { return nil }
        guard value.botID == botID, value.prompt.count <= 7000, !value.prompt.isEmpty else {
            mutationError = "来源草稿无效，请重试"; return nil
        }
        return value
    }

    public func clearError() { listError = nil; mutationError = nil }

    /// Cancellation-insensitive transports cannot apply old account writes or return old context.
    private func perform<T: Sendable>(_ operation: @Sendable (any FeedAPI) async throws -> T) async -> T? {
        guard !busy else { return nil }
        let generation = scopeGeneration
        busy = true; mutationError = nil
        defer { if generation == scopeGeneration { busy = false } }
        do {
            let result = try await operation(api)
            guard generation == scopeGeneration, !Task.isCancelled else { return nil }
            return result
        } catch { record(error, generation: generation); return nil }
    }

    private func record(_ failure: Error, generation: UInt64, isList: Bool = false) {
        guard generation == scopeGeneration, !Task.isCancelled, !(failure is CancellationError) else { return }
        if isList { listError = failure.localizedDescription }
        else { mutationError = failure.localizedDescription }
    }
}
