import Foundation
import Observation
import VeraBotCore
import VeraBotNetworking

/// Account-scoped Drift Bottle state. Real bottle/encounter state comes from the
/// server; the local cache only restores the owner's private turns and drafts.
@MainActor
@Observable
public final class DriftBottleModel {
    public private(set) var state: DriftBottleState?
    public private(set) var current: DriftBottleEncounter?
    public private(set) var bots: [Bot] = []
    public private(set) var selectedBotID: Int?
    public private(set) var records: [DriftBottleRecordSummary] = []
    public private(set) var recordsNextCursor: String?
    public private(set) var isLoading = false
    public private(set) var isWorking = false
    public private(set) var isOffline = false
    public private(set) var isEmptyPool = false
    public private(set) var notice: String?
    public private(set) var quietMode = false
    public private(set) var cachedEncounter: DriftBottleCachedEncounter?
    public private(set) var pendingOperations: [DriftBottlePendingOperation] = []
    public private(set) var drafts: [String: DriftBottleDraft] = [:]
    public private(set) var lastCompletedRecord: DriftBottleRecord?
    /// Bound to the private chat composer. Kept on failure so text is not lost.
    public var chatText = ""

    @ObservationIgnored private var api: (any DriftBottleAPI)?
    @ObservationIgnored private let cache: DriftBottleDraftCache
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let makeRequestID: @Sendable () -> String
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var scopeEpoch: UInt64 = 0
    @ObservationIgnored private var cacheTail: Task<Void, Never>?

    public init(cache: DriftBottleDraftCache = DriftBottleDraftCache(),
                now: @escaping @Sendable () -> Date = { Date() },
                requestID: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.cache = cache
        self.now = now
        self.makeRequestID = requestID
    }

    // MARK: - Derived state

    public var limits: DriftBottleLimits { state?.limits ?? .standard }
    public var selectedBot: Bot? { bots.first { $0.id == selectedBotID } }
    public var hasActiveEncounter: Bool { current?.isActive == true }
    public var privateTurns: [DriftBottleTurn] { current?.turns ?? cachedEncounter?.turns ?? [] }
    public var canDraw: Bool { !isWorking && !hasActiveEncounter }
    public var canWriteNewBottle: Bool { !isWorking && !bots.isEmpty }

    public var currentRecordID: String? {
        current.map { "encounter:\($0.id)" }
    }

    public var pendingRelease: DriftBottlePendingOperation? {
        pendingOperations.first { $0.kind == .release }
    }

    public var pendingChat: DriftBottlePendingOperation? {
        pendingOperations.first { $0.kind == .chat }
    }

    public var offlineMessage: String? {
        isOffline ? "现在连不上网络。你和 Bot 的私人交流与草稿还在；别人写的信件内容需要联网更新。" : nil
    }

    public func bot(id: Int?) -> Bot? {
        guard let id else { return nil }
        return bots.first { $0.id == id }
    }

    // MARK: - Lifecycle

    public func configure(api: any DriftBottleAPI, server: String, userID: Int) async {
        scopeEpoch &+= 1
        let epoch = scopeEpoch
        self.api = api
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        scope = "\(trimmed)|\(userID)"
        state = nil
        current = nil
        records = []
        recordsNextCursor = nil
        isEmptyPool = false
        isOffline = false
        notice = nil
        quietMode = false
        cachedEncounter = nil
        pendingOperations = []
        drafts = [:]
        lastCompletedRecord = nil
        chatText = ""
        if let scope, let saved = try? await cache.load(scope: scope), epoch == scopeEpoch {
            selectedBotID = saved.selectedBotID
            cachedEncounter = saved.activeEncounter
            pendingOperations = saved.pendingOperations
            drafts = saved.drafts
        }
        await load()
        guard epoch == scopeEpoch else { return }
        await recoverPendingOperations()
    }

    public func reset(accountID: Int?) {
        scopeEpoch &+= 1
        api = nil
        scope = nil
        state = nil
        current = nil
        bots = []
        selectedBotID = nil
        records = []
        recordsNextCursor = nil
        isLoading = false
        isWorking = false
        isOffline = false
        isEmptyPool = false
        notice = nil
        quietMode = false
        cachedEncounter = nil
        pendingOperations = []
        drafts = [:]
        lastCompletedRecord = nil
        chatText = ""
        cacheTail?.cancel()
        cacheTail = nil
    }

    public func updateBots(_ newBots: [Bot]) {
        bots = newBots.sorted { $0.id < $1.id }
        if let selectedBotID, !newBots.contains(where: { $0.id == selectedBotID }) {
            self.selectedBotID = newBots.first?.id
        } else if selectedBotID == nil {
            selectedBotID = newBots.first?.id
        }
        persist()
    }

    public func selectBot(_ id: Int?) {
        guard !hasActiveEncounter else { return }
        guard let id, bots.contains(where: { $0.id == id }) else { return }
        selectedBotID = id
        persist()
    }

    public func clearNotice() { notice = nil }

    // MARK: - Loading

    public func load() async {
        guard let api, let epoch = capture() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await api.driftBottleState()
            guard epoch == scopeEpoch else { return }
            state = fresh
            current = fresh.current
            isOffline = false
            if let current {
                quietMode = current.quiet
                remember(current)
            } else {
                cachedEncounter = nil
                rememberActiveEncounter(nil)
            }
        } catch {
            guard epoch == scopeEpoch else { return }
            isOffline = true
            note(error)
        }
    }

    public func refreshCurrent() async {
        guard let api, let encounter = current, let epoch = capture() else { return }
        do {
            let fresh = try await api.driftBottleEncounter(id: encounter.id, cursor: nil)
            guard epoch == scopeEpoch else { return }
            current = fresh
            quietMode = fresh.quiet
            remember(fresh)
        } catch {
            guard epoch == scopeEpoch else { return }
            note(error)
        }
    }

    public func loadEarlier() async {
        guard let api, var encounter = current, let cursor = encounter.nextCursor,
              let epoch = capture() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let page = try await api.driftBottleEncounter(id: encounter.id, cursor: cursor)
            guard epoch == scopeEpoch, current?.id == encounter.id else { return }
            let existing = Set(encounter.contributions.map(\.id))
            encounter.contributions.append(contentsOf: page.contributions.filter { !existing.contains($0.id) })
            encounter.contributions.sort { $0.sequence < $1.sequence }
            encounter.nextCursor = page.nextCursor
            current = encounter
            remember(encounter)
        } catch {
            guard epoch == scopeEpoch else { return }
            note(error)
        }
    }

    public func loadRecords(botID: Int? = nil) async {
        guard let api, let epoch = capture() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.driftBottleRecords(botID: botID, cursor: nil, limit: 20)
            guard epoch == scopeEpoch else { return }
            records = response.records
            recordsNextCursor = response.nextCursor
        } catch {
            guard epoch == scopeEpoch else { return }
            note(error)
        }
    }

    public func loadMoreRecords(botID: Int? = nil) async {
        guard let api, let cursor = recordsNextCursor, let epoch = capture() else { return }
        do {
            let response = try await api.driftBottleRecords(botID: botID, cursor: cursor, limit: 20)
            guard epoch == scopeEpoch else { return }
            let existing = Set(records.map(\.id))
            records.append(contentsOf: response.records.filter { !existing.contains($0.id) })
            recordsNextCursor = response.nextCursor
        } catch {
            guard epoch == scopeEpoch else { return }
            note(error)
        }
    }

    public func record(id: String) async -> DriftBottleRecord? {
        guard let api, let epoch = capture() else { return nil }
        do {
            let record = try await api.driftBottleRecord(id: id)
            guard epoch == scopeEpoch else { return nil }
            return record
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    // MARK: - Bottle flow

    public func draw(botID: Int) async -> DriftBottleEncounter? {
        guard let api, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        let request = DriftBottleDrawRequest(requestID: makeRequestID(), botID: botID)
        do {
            let response = try await api.drawDriftBottle(request)
            guard epoch == scopeEpoch else { return nil }
            isEmptyPool = response.encounter == nil
            current = response.encounter
            if let encounter = response.encounter {
                quietMode = encounter.quiet
                remember(encounter)
                notice = nil
            } else {
                cachedEncounter = nil
                rememberActiveEncounter(nil)
            }
            return response.encounter
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    public func createBottle(botID: Int, text: String,
                             authorship: DriftBottleAuthorship) async -> DriftBottleRecordSummary? {
        guard let api, !isWorking else { return nil }
        guard DriftBottlePresentation.validatePublic(text) == nil else {
            notice = DriftBottlePresentation.validatePublic(text)
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        let request = DriftBottleCreateRequest(requestID: makeRequestID(), botID: botID,
                                               body: text, authorship: authorship)
        do {
            let response = try await api.createDriftBottle(request)
            guard epoch == scopeEpoch else { return nil }
            records.insert(response.record, at: 0)
            clearDraft(forNewBottle: true, encounterID: nil)
            notice = nil
            return response.record
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    public func suggestNewBottleDraft(botID: Int, text: String) async -> String? {
        guard let api, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        let request = DriftBottleDraftSuggestionRequest(requestID: makeRequestID(),
                                                        botID: botID, body: text)
        do {
            let response = try await api.driftBottleDraftSuggestion(request)
            guard epoch == scopeEpoch else { return nil }
            let draft = DriftBottleDraft(text: response.draft,
                                         authorship: DriftBottlePresentation.authorshipAfterGeneration(.owner),
                                         generated: true, updatedAt: now(), encounterID: nil,
                                         bottleID: nil)
            saveDraft(draft, forNewBottle: true, encounterID: nil)
            return response.draft
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    public func suggestEncounterDraft(text: String) async -> String? {
        guard let api, let encounter = current, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        let request = DriftBottleTurnRequest(requestID: makeRequestID(), kind: .draft, text: text)
        do {
            let response = try await api.sendDriftBottleTurn(encounterID: encounter.id, request: request)
            guard epoch == scopeEpoch, current?.id == encounter.id else { return nil }
            current = response.encounter
            remember(response.encounter)
            let draft = DriftBottleDraft(text: response.draft ?? "",
                                         authorship: DriftBottlePresentation.authorshipAfterGeneration(.owner),
                                         generated: true, updatedAt: now(),
                                         encounterID: encounter.id, bottleID: encounter.bottleID)
            saveDraft(draft, forNewBottle: false, encounterID: encounter.id)
            return response.draft
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    public func release(contribution: DriftBottleContributionInput?) async -> DriftBottleRecord? {
        guard let api, let encounter = current, !isWorking else { return nil }
        if let contribution, let problem = DriftBottlePresentation.validatePublic(contribution.body) {
            notice = problem
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        if let existing = pendingRelease, existing.encounterID == encounter.id {
            await recoverPendingOperations()
            guard epoch == scopeEpoch else { return nil }
            if current == nil, let record = lastCompletedRecord,
               record.encounter?.id == encounter.id { return record }
        }
        let requestID = pendingRelease?.requestID ?? makeRequestID()
        let request = DriftBottleReleaseRequest(requestID: requestID,
                                                leaseToken: encounter.leaseToken,
                                                expectedVersion: encounter.bottleVersion,
                                                contribution: contribution)
        addPending(DriftBottlePendingOperation(requestID: requestID, kind: .release,
                                               encounterID: encounter.id))
        do {
            let response = try await api.releaseDriftBottle(encounterID: encounter.id, request: request)
            guard epoch == scopeEpoch else { return nil }
            apply(release: response.record)
            return response.record
        } catch let error as APIError where error.status == 409 || error.status == 404 || error.status == 422 {
            guard epoch == scopeEpoch else { return nil }
            removePending(requestID: requestID)
            notice = error.message
            await load()
            return nil
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            notice = "这次放漂还没有确认结果。文字还在本机，稍后可以重试；如果已经成功，不会重复留言。"
            return nil
        }
    }

    public func requestOpening(quiet: Bool = false) async {
        guard let api, let encounter = current, encounter.isActive else { return }
        if quiet {
            guard !encounter.quiet else { quietMode = true; return }
            guard !isWorking else { return }
            isWorking = true
            defer { isWorking = false }
            let epoch = captureEpoch()
            let request = DriftBottleTurnRequest(requestID: makeRequestID(), kind: .opening, quiet: true)
            do {
                let response = try await api.sendDriftBottleTurn(encounterID: encounter.id, request: request)
                guard epoch == scopeEpoch, current?.id == encounter.id else { return }
                apply(turn: response)
                quietMode = true
            } catch {
                guard epoch == scopeEpoch else { return }
                quietMode = true
            }
            return
        }
        guard !encounter.quiet,
              !encounter.turns.contains(where: { $0.kind == .opening }),
              !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        let request = DriftBottleTurnRequest(requestID: makeRequestID(), kind: .opening)
        do {
            let response = try await api.sendDriftBottleTurn(encounterID: encounter.id, request: request)
            guard epoch == scopeEpoch, current?.id == encounter.id else { return }
            apply(turn: response)
        } catch {
            // Opening failure never blocks reading, writing or returning the bottle.
            guard epoch == scopeEpoch else { return }
            notice = "Bot 这次没有开口，你可以安静读一会儿，也可以自己先写。"
        }
    }

    public func loadEncounter(id: Int) async -> DriftBottleEncounter? {
        guard let api, let epoch = capture() else { return nil }
        do {
            let encounter = try await api.driftBottleEncounter(id: id, cursor: nil)
            guard epoch == scopeEpoch else { return nil }
            current = encounter
            quietMode = encounter.quiet
            remember(encounter)
            return encounter
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    /// Continue a private conversation from a completed record without
    /// reopening the bottle or implying that public writing is possible.
    public func send(message: String, to encounterID: Int) async -> DriftBottleTurn? {
        guard let api, !isWorking else { return nil }
        if let problem = DriftBottlePresentation.validateChat(message) {
            notice = problem
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        let request = DriftBottleTurnRequest(requestID: makeRequestID(), kind: .chat, text: message)
        do {
            let response = try await api.sendDriftBottleTurn(encounterID: encounterID, request: request)
            guard epoch == scopeEpoch else { return nil }
            if current?.id == encounterID { apply(turn: response) }
            notice = nil
            return response.turn
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    public func setQuiet(_ value: Bool) {
        quietMode = value
    }

    public func send(message: String) async -> Bool {
        guard let api, let encounter = current, !isWorking else { return false }
        if let problem = DriftBottlePresentation.validateChat(message) {
            notice = problem
            return false
        }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        if let existing = pendingChat, existing.encounterID == encounter.id, existing.text == message {
            await recoverPendingOperations()
            guard epoch == scopeEpoch else { return false }
            if pendingChat == nil { return true }
        }
        let requestID = pendingChat?.requestID ?? makeRequestID()
        let request = DriftBottleTurnRequest(requestID: requestID, kind: .chat, text: message)
        addPending(DriftBottlePendingOperation(requestID: requestID, kind: .chat,
                                               encounterID: encounter.id, text: message))
        do {
            let response = try await api.sendDriftBottleTurn(encounterID: encounter.id, request: request)
            guard epoch == scopeEpoch, current?.id == encounter.id else { return false }
            apply(turn: response)
            removePending(requestID: requestID)
            chatText = ""
            notice = nil
            return true
        } catch let error as APIError where error.status == 400 || error.status == 404 ||
                                            error.status == 409 || error.status == 422 {
            guard epoch == scopeEpoch else { return false }
            removePending(requestID: requestID)
            notice = error.message
            return false
        } catch {
            guard epoch == scopeEpoch else { return false }
            note(error)
            notice = "这句话还没确认送到。文字还在，可以稍后重试；不会重复出现。"
            return false
        }
    }

    public func recoverPendingOperations() async {
        guard let api else { return }
        let epoch = captureEpoch()
        for operation in pendingOperations {
            do {
                let envelope = try await api.driftBottleOperation(requestID: operation.requestID)
                guard epoch == scopeEpoch else { return }
                guard envelope.operation.status == .committed else {
                    if envelope.operation.status == .failed {
                        notice = envelope.operation.errorMessage ?? "上次操作没有完成，可以重试。"
                    }
                    continue
                }
                switch operation.kind {
                case .release:
                    if let result: DriftBottleReleaseResult = decode(envelope.result) {
                        apply(release: result.record)
                    }
                case .chat:
                    if let result: DriftBottleTurnResult = decode(envelope.result),
                       result.encounter.id == operation.encounterID {
                        apply(turn: result)
                        removePending(requestID: operation.requestID)
                        chatText = ""
                    }
                }
            } catch let error as APIError where error.status == 404 {
                continue
            } catch {
                guard epoch == scopeEpoch else { return }
                note(error)
            }
        }
    }

    // MARK: - Moderation and memories

    public func withdraw(contributionID: Int) async -> DriftBottlePublicContribution? {
        guard let api, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        do {
            let response = try await api.withdrawDriftBottleContribution(
                id: contributionID, request: DriftBottleWithdrawRequest(requestID: makeRequestID()))
            guard epoch == scopeEpoch else { return nil }
            await refreshCurrent()
            return response.contribution
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    public func report(contributionID: Int, reason: String) async -> Bool {
        guard let api, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        do {
            _ = try await api.reportDriftBottleContribution(DriftBottleReportRequest(
                requestID: makeRequestID(), contributionID: contributionID, reason: reason))
            guard epoch == scopeEpoch else { return false }
            await refreshCurrent()
            return true
        } catch {
            guard epoch == scopeEpoch else { return false }
            note(error)
            return false
        }
    }

    public func block(contributionID: Int) async -> Bool {
        guard let api, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        do {
            _ = try await api.blockDriftBottleContributor(DriftBottleBlockRequest(
                requestID: makeRequestID(), contributionID: contributionID))
            guard epoch == scopeEpoch else { return false }
            await refreshCurrent()
            return true
        } catch {
            guard epoch == scopeEpoch else { return false }
            note(error)
            return false
        }
    }

    public func generateMemory(encounterID: Int) async -> DriftBottleMemory? {
        guard let api, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        do {
            let response = try await api.generateDriftBottleMemory(
                encounterID: encounterID,
                request: DriftBottleMemoryRequest(requestID: makeRequestID()))
            guard epoch == scopeEpoch else { return nil }
            if current?.id == encounterID { current?.memory = response.memory }
            return response.memory
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    public func patchMemory(recordID: String, patch: DriftBottleMemoryPatch) async -> DriftBottleMemory? {
        guard let api, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        do {
            let response = try await api.patchDriftBottleMemory(recordID: recordID,
                                                                requestID: makeRequestID(),
                                                                patch: patch)
            guard epoch == scopeEpoch else { return nil }
            if var current, "encounter:\(current.id)" == recordID { current.memory = response.memory; self.current = current }
            return response.memory
        } catch {
            guard epoch == scopeEpoch else { return nil }
            note(error)
            return nil
        }
    }

    public func deleteMemory(recordID: String) async -> Bool {
        guard let api, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        do {
            _ = try await api.deleteDriftBottleMemory(recordID: recordID, requestID: makeRequestID())
            guard epoch == scopeEpoch else { return false }
            if var current, "encounter:\(current.id)" == recordID { current.memory = nil; self.current = current }
            return true
        } catch {
            guard epoch == scopeEpoch else { return false }
            note(error)
            return false
        }
    }

    public func deleteRecord(id: String) async -> Bool {
        guard let api, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let epoch = captureEpoch()
        do {
            _ = try await api.deleteDriftBottleRecord(id: id, requestID: makeRequestID())
            guard epoch == scopeEpoch else { return false }
            records.removeAll { $0.id == id }
            if let current, "encounter:\(current.id)" == id { self.current = nil }
            return true
        } catch {
            guard epoch == scopeEpoch else { return false }
            note(error)
            return false
        }
    }

    // MARK: - Drafts

    public func draft(forNewBottle: Bool, encounterID: Int? = nil) -> DriftBottleDraft? {
        drafts[draftKey(forNewBottle: forNewBottle, encounterID: encounterID)]
    }

    public func saveDraft(text: String, authorship: DriftBottleAuthorship, generated: Bool = false,
                          forNewBottle: Bool, encounterID: Int? = nil, bottleID: Int? = nil) {
        let key = draftKey(forNewBottle: forNewBottle, encounterID: encounterID)
        drafts[key] = DriftBottleDraft(text: text, authorship: authorship, generated: generated,
                                       updatedAt: now(), encounterID: encounterID, bottleID: bottleID)
        persist()
    }

    private func saveDraft(_ draft: DriftBottleDraft, forNewBottle: Bool, encounterID: Int?) {
        drafts[draftKey(forNewBottle: forNewBottle, encounterID: encounterID)] = draft
        persist()
    }

    public func clearDraft(forNewBottle: Bool, encounterID: Int? = nil) {
        drafts.removeValue(forKey: draftKey(forNewBottle: forNewBottle, encounterID: encounterID))
        persist()
    }

    private func draftKey(forNewBottle: Bool, encounterID: Int?) -> String {
        if forNewBottle { return "new" }
        return "encounter:\(encounterID ?? current?.id ?? 0)"
    }

    // MARK: - Cache and helpers

    public func flushCache() async {
        await cacheTail?.value
    }

    private func capture() -> UInt64? {
        guard api != nil else { return nil }
        return scopeEpoch
    }

    private func captureEpoch() -> UInt64 { scopeEpoch }

    private func note(_ error: Error) {
        if let api = error as? APIError {
            notice = api.message
        } else if (error as NSError).domain == NSURLErrorDomain {
            notice = "暂时连不上网络。你的草稿和私人交流还在，稍后再试。"
        } else {
            notice = "这次没有连接成功，稍后再试；你的文字还在。"
        }
    }

    private func remember(_ encounter: DriftBottleEncounter) {
        guard encounter.isActive else {
            rememberActiveEncounter(nil)
            return
        }
        cachedEncounter = DriftBottleCachedEncounter(encounter: encounter)
        persist()
    }

    private func rememberActiveEncounter(_ encounter: DriftBottleCachedEncounter?) {
        cachedEncounter = encounter
        persist()
    }

    private func addPending(_ operation: DriftBottlePendingOperation) {
        pendingOperations.removeAll { $0.requestID == operation.requestID }
        pendingOperations.append(operation)
        persist()
    }

    private func removePending(requestID: String) {
        pendingOperations.removeAll { $0.requestID == requestID }
        persist()
    }

    private func apply(release record: DriftBottleRecord) {
        let encounterID = record.encounter?.id ?? current?.id
        lastCompletedRecord = record
        current = nil
        quietMode = false
        isEmptyPool = false
        pendingOperations.removeAll { $0.kind == .release && $0.encounterID == encounterID }
        cachedEncounter = nil
        chatText = ""
        if let encounterID { drafts["encounter:\(encounterID)"] = nil }
        let summary = summary(from: record)
        records.removeAll { $0.id == summary.id }
        records.insert(summary, at: 0)
        notice = nil
        persist()
    }

    private func apply(turn response: DriftBottleTurnResponse) {
        apply(turn: DriftBottleTurnResult(encounter: response.encounter,
                                          turn: response.turn, draft: response.draft))
    }

    private func apply(turn result: DriftBottleTurnResult) {
        current = result.encounter
        quietMode = result.encounter.quiet
        remember(result.encounter)
    }

    private func summary(from record: DriftBottleRecord) -> DriftBottleRecordSummary {
        let encounter = record.encounter
        return DriftBottleRecordSummary(
            id: record.id, kind: record.kind, title: record.title, subtitle: record.subtitle,
            botID: encounter?.botID, botName: encounter?.botName ?? "",
            botAvatar: encounter?.botAvatar ?? "🤖", botColor: encounter?.botColor ?? "#0F766E",
            createdAt: record.createdAt, completedAt: record.completedAt,
            hasMemory: record.memory != nil,
            contributionCount: encounter?.readLimit ?? record.contributions.count)
    }

    private func decode<T: Decodable>(_ value: JSONValue?) -> T? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persist() {
        guard let scope else { return }
        var active = cachedEncounter
        if let current { active = current.isActive ? DriftBottleCachedEncounter(encounter: current) : nil }
        let record = DriftBottleLocalRecord(
            scope: scope,
            selectedBotID: selectedBotID,
            activeEncounter: active,
            drafts: drafts,
            pendingOperations: pendingOperations)
        let cache = self.cache
        let previous = cacheTail
        cacheTail = Task {
            await previous?.value
            try? await cache.save(record, scope: scope)
        }
    }
}
