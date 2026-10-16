import SwiftUI
import VeraBotCore
import VeraBotNetworking
import VeraBotData

@MainActor
@Observable
final class ChatViewModel {
    struct Item: Identifiable {
        let id: UUID
        let isUser: Bool
        var text: String
        var traces: [ToolTrace] = []
        var streaming = false
        var messageID: Int?
        var attachments: [Attachment] = []   // 用户消息里的图片（v12）
        var feedback: MessageFeedback?       // assistant 消息的 👍 / 👎（M2）
        var sortKey: Int = 0
        var localStatus = "synced"
        var publicationRevision = 0
        var generation = 1

        init(id: UUID = UUID(), isUser: Bool, text: String, traces: [ToolTrace] = [], streaming: Bool = false,
             messageID: Int? = nil, attachments: [Attachment] = [], feedback: MessageFeedback? = nil,
             sortKey: Int = 0, localStatus: String = "synced") {
            self.id = id; self.isUser = isUser; self.text = text; self.traces = traces; self.streaming = streaming
            self.messageID = messageID; self.attachments = attachments; self.feedback = feedback
            self.sortKey = sortKey; self.localStatus = localStatus
        }
    }

    var bot: Bot
    let api: any VeraBotAPI   // 气泡里的图片也用它下载（鉴权、no-store）
    let repository: ConversationRepository?
    var historyIncomplete = false
    var loadingOlder = false
    var hasOlderMessages = false
    var items: [Item] = []
    var activityRepository: ConversationActivityRepository?
    var replyTasks: [ChatReplyTask] = []
    /// 正在排队或生成的回复：此时输入栏右侧显示忙碌 / 停止按钮，不允许再发新消息。
    var replyInProgress: ChatReplyTask? { replyTasks.first { $0.state == "queued" || $0.state == "running" } }
    var conversationGeneration = 1
    var controlBusy: Set<Int> = []
    var selectedWaitTaskID: Int?
    private var detailObservation: Task<Void, Never>?
    private var recoveryRetry: Task<Void, Never>?
    private var detailCursor = 0
    private var pageEpoch = 0
    private var projection = ChatReplyProjection()
    var sending = false
    /// 这一页只显示一条通知：连不上时是「暂时连接不上」，待确认句子保持原文。
    var notice: PageNotice?
    var scrollTick = 0
    /// 对话中记忆确认卡片的服务器状态（memory_id → 最新 Memory；nil 值 = 已不存在）
    var memoryStates: [Int: Memory?] = [:]
    /// 本机刚处理过、服务器上已删除的提议（如「忘掉」确认后提议本身被删除）：memory_id → 结果文案
    var memoryOutcomes: [Int: String] = [:]
    var memoryBusy: Set<Int> = []
    var memoryConfirmTick = 0   // 触感反馈触发器：确认记住 +1
    var candidateMemoryCount = 0
    var memorySuggestions: [MemorySuggestion] = []
    var suggestionBusy: Set<Int> = []
    var suggestionErrors: [Int: String] = [:]
    var openBotSettingsTick = 0
    var quickPrompts: [String] = []
    /// 已展开的长回复（键同对话行 id：有 messageID 为 "m<id>"，否则本地 UUID）；只在本页存活期间保留。
    var expandedReplies: Set<String> = []
    /// MCP M3 确认卡片：action_id → 最新 PendingAction
    var actionStates: [Int: PendingAction] = [:]
    var actionBusy: Set<Int> = []
    /// 执行状态机与头像计时（对话页导航栏读取 `executionState`）。
    private var playback = ExecutionAvatarController()
    var executionState: ExecutionState { replyTasks.first(where: { $0.state == "awaiting_user" || $0.state == "awaiting_approval" })?.executionState ?? replyTasks.first(where: { $0.state == "running" })?.executionState ?? playback.state }
    private var blockedTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?

    /// 状态机输入的唯一入口。命令由 `ExecutionAvatarController` 决定：受阻 1.2 s 后回到原流程，
    /// 正常结束 1.5 s 后回到空闲；`reset`、提前离开或新一轮会取消尚未触发的计时。
    private func feed(_ event: ExecutionEvent) {
        apply(playback.send(event))
    }

    private func apply(_ commands: [ExecutionTimerCommand]) {
        for command in commands {
            switch command {
            case .cancelBlocked:
                blockedTask?.cancel()
                blockedTask = nil
            case .startBlocked(let serial):
                blockedTask?.cancel()
                blockedTask = Task { [weak self] in
                    try? await Task.sleep(for: ExecutionStateMachine.blockedDisplayDuration)
                    guard let self, !Task.isCancelled else { return }
                    self.apply(self.playback.blockedFired(serial: serial))
                }
            case .cancelIdle:
                idleTask?.cancel()
                idleTask = nil
            case .startIdle:
                idleTask?.cancel()
                idleTask = Task { [weak self] in
                    try? await Task.sleep(for: ExecutionStateMachine.completedIdleDelay)
                    guard let self, !Task.isCancelled else { return }
                    self.apply(self.playback.idleFired())
                }
            }
        }
    }

    init(bot: Bot, api: any VeraBotAPI, repository: ConversationRepository? = nil) {
        self.bot = bot
        self.api = api
        self.repository = repository
    }

    func load(localReady: @MainActor () async -> Void = {}) async {
        await restoreLocal()
        if items.isEmpty && !historyIncomplete {
            items = [Item(isUser: false, text: openingText())]
        }
        // Reading and initial positioning must never wait for the network.
        await localReady()
        guard !Task.isCancelled else { return }
        if let repository {
            do {
                try await repository.syncPrivate(botID: bot.id)
                let restored = await restoreLocal()
                historyIncomplete = false
                if restored, notice?.offline == true { notice = nil }
            } catch {
                historyIncomplete = !((try? await repository.isHistoryComplete(kind: .privateChat, id: bot.id)) ?? false)
                if !items.isEmpty {
                    notice = PageNotice(offline: true, detail: "仍可查看已同步的历史。", allowsRetry: true)
                } else if historyIncomplete {
                    notice = PageNotice(offline: true, allowsRetry: true)
                } else {
                    notice = .fromLoad(error, message: UserFacingError.message(for: error))
                }
            }
        } else {
            do {
                let response = try await api.messages(botID: bot.id)
                items = response.messages.map {
                    Item(isUser: $0.role == "user", text: $0.content, traces: $0.traces ?? [], messageID: $0.id,
                         attachments: $0.attachments, feedback: $0.feedback, sortKey: $0.id)
                }
                historyIncomplete = response.messages.count >= 100
                if notice?.offline == true { notice = nil }
            } catch { notice = .fromLoad(error, message: UserFacingError.message(for: error)) }
        }
        await recoverExecution()
        if items.isEmpty && !historyIncomplete {
            items = [Item(isUser: false, text: openingText())]
            Task { await ensureOpeningTemplatesIfNeeded() }
        }
        scrollTick += 1
        await refreshMemoryStates()
        await refreshPendingActions()
        await refreshCandidateMemories()
        await refreshMemorySuggestions()
    }

    /// 空对话开场词：本地组装，不调模型。见 docs/specs/bot-opening-message.md。
    var preferredAddress: String?

    private func openingText() -> String {
        let fromMemory = OpeningMessageComposer.cleanedAddress(bot.openingAddress)
        let fromAccount = OpeningMessageComposer.cleanedAddress(preferredAddress)
        let address = fromMemory.isEmpty ? (fromAccount.isEmpty ? nil : fromAccount) : fromMemory
        return OpeningMessageComposer.compose(
            botName: bot.name,
            persona: bot.persona,
            templates: bot.openingTemplates,
            address: address,
            conversationGeneration: conversationGeneration
        )
    }

    private func ensureOpeningTemplatesIfNeeded() async {
        guard bot.openingTemplates == nil else { return }
        do {
            let updated = try await api.ensureOpeningTemplates(botID: bot.id)
            bot = bot.replacingOpening(templates: updated.openingTemplates, address: updated.openingAddress ?? bot.openingAddress)
        } catch {
            // 兜底已展示；后台生成失败不影响本次空对话。
        }
    }

    @discardableResult
    private func restoreLocal() async -> Bool {
        guard let repository else { return true }
        do {
            let visibleLimit = max(100, items.count)
            let stored = try await repository.privateMessages(botID: bot.id, limit: visibleLimit + 1)
            hasOlderMessages = stored.count > visibleLimit
            items = stored.suffix(visibleLimit).map { row in
                let message = row.value
                return Item(id: message.id, isUser: message.role == "user", text: message.content,
                            traces: message.traces, streaming: false, messageID: message.remoteID,
                            attachments: message.attachments, feedback: message.feedback,
                            sortKey: row.sortKey,
                            localStatus: row.status == "receiving" ? (message.content.isEmpty ? "unconfirmed" : "interrupted") : row.status)
            }
            for row in stored {
                if let index = items.firstIndex(where: { $0.id == row.value.id }) {
                    items[index].publicationRevision = row.value.publicationRevision ?? 0
                    items[index].generation = row.value.generation ?? 1
                    items[index].streaming = row.value.messageStatus == "running" || row.value.messageStatus == "queued"
                }
            }
            historyIncomplete = !(try await repository.isHistoryComplete(kind: .privateChat, id: bot.id))
            return true
        } catch {
            historyIncomplete = true
            notice = PageNotice(offline: true, detail: "本地历史暂时无法读取。", allowsRetry: true)
            return false
        }
    }

    func loadOlder() async {
        guard let repository, !loadingOlder, let first = items.first else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await repository.privateMessages(botID: bot.id, before: first.sortKey, limit: 101)
            hasOlderMessages = page.count > 100
            let older = page.suffix(100).map { row in
                Item(id: row.value.id, isUser: row.value.role == "user", text: row.value.content,
                     traces: row.value.traces, messageID: row.value.remoteID, attachments: row.value.attachments,
                     feedback: row.value.feedback, sortKey: row.sortKey, localStatus: row.status)
            }
            items.insert(contentsOf: older, at: 0)
        } catch { notice = PageNotice(offline: true, detail: "本地历史暂时无法读取。", allowsRetry: true) }
    }

    func ensureMessageLoaded(_ id: Int) async {
        while hasOlderMessages && !items.contains(where: { $0.messageID == id }) {
            let first = items.first?.id
            await loadOlder()
            if items.first?.id == first { break }
        }
    }
    func loadDraft() async -> String {
        (try? await repository?.draft(kind: .privateChat, id: bot.id)) ?? ""
    }

    func saveDraft(_ text: String) async {
        try? await repository?.saveDraft(text, kind: .privateChat, id: bot.id)
    }

    private func persist(_ item: Item, status: String) async {
        guard let repository else { return }
        let message = LocalPrivateMessage(id: item.id, remoteID: item.messageID,
                                          role: item.isUser ? "user" : "assistant", content: item.text,
                                          traces: item.traces, attachments: item.attachments,
                                          feedback: item.feedback, localStatus: status, generation: item.generation, publicationRevision: item.publicationRevision, messageStatus: status)
        try? await repository.savePrivate(message, botID: bot.id,
                                          sortKey: item.sortKey,
                                          status: status)
    }

    func refreshCandidateMemories() async {
        guard bot.memoryAccess != .none else { candidateMemoryCount = 0; return }
        do {
            let response = try await api.memories(MemoryQuery(statuses: [.candidate], visibleTo: bot.id))
            candidateMemoryCount = response.memories.count
        } catch {
            candidateMemoryCount = 0
        }
    }

    func refreshMemorySuggestions() async {
        do {
            memorySuggestions = try await api.memorySuggestions(botID: bot.id).suggestions
        } catch {
            memorySuggestions = []
        }
    }

    func refreshQuickPrompts() async {
        do {
            quickPrompts = try await api.quickPrompts(botID: bot.id).prompts
        } catch {
            quickPrompts = []
        }
    }

    func acceptMemorySuggestion(_ id: Int) async {
        suggestionBusy.insert(id)
        suggestionErrors[id] = nil
        defer { suggestionBusy.remove(id) }
        do {
            let result = try await api.decideMemorySuggestion(id: id, accept: true)
            if result.status == "accepted", result.settingsBotID != nil { openBotSettingsTick += 1 }
            await refreshMemorySuggestions()
        } catch let error as APIError {
            suggestionErrors[id] = error.message
        } catch {
            suggestionErrors[id] = "操作失败，请稍后重试。"
        }
    }

    func dismissMemorySuggestion(_ id: Int) async {
        suggestionBusy.insert(id)
        suggestionErrors[id] = nil
        defer { suggestionBusy.remove(id) }
        do {
            _ = try await api.decideMemorySuggestion(id: id, accept: false)
            await refreshMemorySuggestions()
        } catch let error as APIError {
            suggestionErrors[id] = error.message
        } catch {
            suggestionErrors[id] = "操作失败，请稍后重试。"
        }
    }

    // MARK: - MCP M3 确认卡片

    private var pendingActionIDs: [Int] {
        items.flatMap { $0.traces.compactMap { $0.pendingConfirmation?.actionId } }
    }

    func refreshPendingActions() async {
        do {
            let remote = try await api.pendingActions(status: "pending", botID: bot.id)
            for a in remote.actions {
                actionStates[a.id] = a
            }
            // 历史里出现过、但不在 pending 列表的：拉一次最新状态
            for id in Set(pendingActionIDs) where actionStates[id] == nil {
                if let a = try? await api.pendingAction(id: id) {
                    actionStates[id] = a
                }
            }
        } catch {
            // 旧后端无此接口：忽略
        }
    }

    func confirmAction(_ id: Int) async {
        actionBusy.insert(id)
        defer { actionBusy.remove(id) }
        do {
            let a = try await api.confirmPendingAction(id: id)
            actionStates[id] = a
            memoryConfirmTick += 1
        } catch let e as APIError where e.status == 410 {
            actionStates[id] = actionStates[id].map {
                PendingAction(id: $0.id, kind: $0.kind, status: "expired", botId: $0.botId,
                              serverId: $0.serverId, server: $0.server, tool: $0.tool, label: $0.label,
                              risk: $0.risk, arguments: $0.arguments, warnings: $0.warnings,
                              result: "已过期", createdAt: $0.createdAt, expiresAt: $0.expiresAt,
                              decidedAt: $0.decidedAt)
            } ?? PendingAction(id: id, status: "expired", result: "已过期")
            notice = .sentence(e.message)
        } catch let e as APIError {
            notice = .sentence(e.message)
            if e.status == 409, let a = try? await api.pendingAction(id: id) {
                actionStates[id] = a
            }
        } catch {
            notice = .fromAction(error, message: UserFacingError.message(for: error))
        }
    }

    func cancelAction(_ id: Int) async {
        actionBusy.insert(id)
        defer { actionBusy.remove(id) }
        do {
            actionStates[id] = try await api.cancelPendingAction(id: id)
        } catch let e as APIError {
            notice = .sentence(e.message)
            if e.status == 409 || e.status == 410, let a = try? await api.pendingAction(id: id) {
                actionStates[id] = a
            }
        } catch {
            notice = .fromAction(error, message: UserFacingError.message(for: error))
        }
    }

    // MARK: - 记忆确认卡片（remember / forget_memory 的 trace）

    private var proposalIDs: [Int] {
        items.flatMap { $0.traces.compactMap { $0.memoryProposal }.filter(\.isCard).compactMap(\.memoryID) }
    }

    /// 批量刷新卡片状态（历史重载 / 跨设备都以服务器为准）。不存在的 id 记为 nil（已删除）。
    func refreshMemoryStates() async {
        let ids = Array(Set(proposalIDs)).sorted().suffix(50)
        guard !ids.isEmpty else { return }
        do {
            let r = try await api.memories(MemoryQuery(statuses: [.proposed, .candidate, .active, .rejected, .expired],
                                                       ids: Array(ids)))
            var next: [Int: Memory?] = [:]
            for id in ids { next[id] = .some(nil) }
            for m in r.memories { next[m.id] = m }
            memoryStates.merge(next) { _, new in new }
        } catch {
            // 刷新失败时保留卡片当时的状态（proposed），用户仍可点按，服务器会返回真实结果
        }
    }

    func confirmMemory(_ id: Int, content: String? = nil) async {
        memoryBusy.insert(id)
        defer { memoryBusy.remove(id) }
        do {
            switch try await api.confirmMemory(id: id, content: content) {
            case .memory(let m):
                memoryStates[id] = m
            case .deleted:
                memoryStates[id] = .some(nil)
                memoryOutcomes[id] = "已忘掉"
            }
            memoryConfirmTick += 1
            feed(.confirmationResolved(memoryID: id))
        } catch {
            await handleMemoryError(error, id: id)
        }
    }

    func rejectMemory(_ id: Int) async {
        memoryBusy.insert(id)
        defer { memoryBusy.remove(id) }
        do {
            _ = try await api.rejectMemory(id: id)
            memoryOutcomes[id] = "已忽略"
            feed(.confirmationResolved(memoryID: id))
            await refreshMemoryStates()
        } catch {
            await handleMemoryError(error, id: id)
        }
    }

    /// 422（编辑后的内容未通过策略）显示服务器文案；404 / 409 / 410 以服务器最新状态为准。
    private func handleMemoryError(_ error: Error, id: Int) async {
        if let e = error as? APIError, [404, 409, 410].contains(e.status) {
            await refreshMemoryStates()
            if e.status == 404 { memoryStates[id] = .some(nil) }
        } else {
            notice = .fromAction(error, message: UserFacingError.message(for: error))
        }
    }

    /// BUG-07：回复为空时不再在错误前拼接空行
    private func appendError(_ msg: String, at idx: Int) {
        let t = items[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].text = t.isEmpty ? "⚠️ \(msg)" : items[idx].text + "\n\n⚠️ \(msg)"
    }

    var feedbackBusy: Set<Int> = []

    /// 👍 / 👎。rating = 1 不带原因；rating = -1 必须带 reason。服务端若提议风格记忆，把确认卡片接到这条回复上。
    func setFeedback(messageID: Int, rating: Int, reason: String?) async {
        feedbackBusy.insert(messageID)
        defer { feedbackBusy.remove(messageID) }
        do {
            let r = try await api.setMessageFeedback(messageID: messageID, rating: rating, reason: reason)
            guard let idx = items.firstIndex(where: { $0.messageID == messageID }) else { return }
            items[idx].feedback = r.feedback
            if let trace = r.styleTrace, !items[idx].traces.contains(where: { $0.id == trace.id }) {
                items[idx].traces.append(trace)
            }
            if items[idx].traces.contains(where: { $0.memoryProposal?.isCard == true }) {
                await refreshMemoryStates()
            }
        } catch {
            notice = .fromAction(error, message: UserFacingError.message(for: error))
        }
    }

    func clearFeedback(messageID: Int) async {
        feedbackBusy.insert(messageID)
        defer { feedbackBusy.remove(messageID) }
        do {
            _ = try await api.deleteMessageFeedback(messageID: messageID)
            if let idx = items.firstIndex(where: { $0.messageID == messageID }) {
                items[idx].feedback = nil
            }
        } catch {
            notice = .fromAction(error, message: UserFacingError.message(for: error))
        }
    }

    /// 清空对话；includeMemories = true 时同时删除该 Bot 的「本 Bot 记忆」。对话摘要总会删掉，已确认的记忆默认保留。
    func clear(includeMemories: Bool = false) async {
        notice = nil
        do {
            _ = try await api.clearMessages(botID: bot.id, includeMemories: includeMemories)
        } catch {
            notice = .fromAction(error, message: UserFacingError.message(for: error))
            return
        }
        try? await repository?.clearPrivate(botID: bot.id)
        memoryStates = [:]
        memoryOutcomes = [:]
        actionStates = [:]
        feed(.reset)
        await load()
    }

    /// 删除单条消息：只对已落库（有 messageID）且不在流式输出中的条目生效；成功后从列表移除，失败显示在这一页的通知上。
    func delete(_ item: Item) async {
        guard let mid = item.messageID, !item.streaming else { return }
        do {
            _ = try await api.deleteMessage(botID: bot.id, messageID: mid)
            items.removeAll { $0.messageID == mid }
            try? await repository?.deletePrivate(LocalPrivateMessage(id: item.id, remoteID: mid,
                                                                      role: item.isUser ? "user" : "assistant",
                                                                      content: item.text, traces: item.traces,
                                                                      attachments: item.attachments, feedback: item.feedback), botID: bot.id)
        } catch let e as APIError where e.status == 404 {
            items.removeAll { $0.messageID == mid }   // 服务器上已不存在（如另一台设备已删除），以服务器为准
            try? await repository?.deletePrivate(LocalPrivateMessage(id: item.id, remoteID: mid,
                                                                      role: item.isUser ? "user" : "assistant", content: item.text), botID: bot.id)
        } catch {
            notice = .fromAction(error, message: UserFacingError.message(for: error))
        }
    }

    func leave() {
        pageEpoch += 1
        detailObservation?.cancel(); detailObservation = nil
        recoveryRetry?.cancel(); recoveryRetry = nil
        // Observation and speech have page lifetimes; accepted server work does not.
    }

    func recoverExecution() async {
        let epoch = pageEpoch
        if let pending = try? await activityRepository?.pending(botID: bot.id) {
            for input in pending where !items.contains(where: { $0.id == UUID(uuidString: input.clientRequestID) }) {
                let sort = (items.last?.sortKey ?? 0) + 1
                items.append(Item(id: UUID(uuidString: input.clientRequestID) ?? UUID(), isUser: true, text: input.message, sortKey: sort, localStatus: "sending"))
                items.append(Item(id: pendingAssistantID(input.clientRequestID), isUser: false, text: "发送结果待确认", sortKey: sort + 1, localStatus: "pending:\(input.clientRequestID)"))
            }
        }
        if let cached = try? await activityRepository?.cached(ChatExecutionSnapshot.self, key: "execution:\(bot.id)") { await applySnapshot(cached) }
        do {
            let snapshot = try await api.chatExecution(botID: bot.id)
            guard epoch == pageEpoch, !Task.isCancelled else { return }
            await applySnapshot(snapshot)
            if let pending = try await activityRepository?.pending(botID: bot.id) {
                for input in pending where input.expectedGeneration == snapshot.generation {
                    do {
                        let receipt: ChatInputReceipt
                        do { receipt = try await api.chatInputReceipt(botID: bot.id, requestID: input.clientRequestID) }
                        catch let error as APIError where error.status == 404 && error.code == "not_accepted" { receipt = try await api.submitChatInput(botID: bot.id, input: input) }
                        guard epoch == pageEpoch else { return }
                        // Receipts preserve original generation/state. Refresh before using one after an uncertain send.
                        let fresh = try await api.chatExecution(botID: bot.id)
                        await applySnapshot(fresh)
                        if receipt.generation == fresh.generation { bindReceipt(receipt, input: input) }
                        try await activityRepository?.removePending(botID: bot.id, requestID: input.clientRequestID)
                    } catch {
                        if let error = error as? APIError, (400..<500).contains(error.status), error.status != 408 {
                            try? await activityRepository?.removePending(botID: bot.id, requestID: input.clientRequestID)
                            notice = .sentence(error.message)
                        } else { notice = .sentence("发送结果待确认，恢复网络后会继续核对。") }
                    }
                }
            }
            if let controls = try await activityRepository?.pendingControls(botID: bot.id) {
                for control in controls where control.generation == conversationGeneration {
                    do { try await submitControl(control); guard epoch == pageEpoch else { return } }
                    catch { notice = .sentence("操作结果待确认，恢复网络后会继续核对。") }
                }
                if !controls.isEmpty { let fresh = try await api.chatExecution(botID: bot.id); guard epoch == pageEpoch else { return }; await applySnapshot(fresh) }
            }
            startObservation()
            let pendingInputs = (try? await activityRepository?.pending(botID: bot.id)) ?? []
            let pendingControls = (try? await activityRepository?.pendingControls(botID: bot.id)) ?? []
            if !pendingInputs.isEmpty || !pendingControls.isEmpty { scheduleRecovery() }
        } catch { if !Task.isCancelled && epoch == pageEpoch { notice = .sentence("待同步；已接收的回复会继续执行。"); scheduleRecovery() } }
    }

    private func scheduleRecovery() {
        guard recoveryRetry == nil else { return }
        let epoch = pageEpoch
        recoveryRetry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self, epoch == self.pageEpoch else { return }
            self.recoveryRetry = nil
            await self.recoverExecution()
        }
    }
    private func pendingAssistantID(_ requestID: String) -> UUID {
        guard let value = UUID(uuidString: requestID) else { return UUID() }
        var bytes = value.uuid; bytes.0 ^= 255
        return UUID(uuid: bytes)
    }
    private func bindReceipt(_ receipt: ChatInputReceipt, input: ChatInputRequest) {
        guard receipt.generation == conversationGeneration else { return }
        let userID = UUID(uuidString: input.clientRequestID)
        if let index = items.firstIndex(where: { $0.id == userID }) { items[index].messageID = receipt.userMessageID; items[index].sortKey = receipt.userMessageID; items[index].localStatus = "synced" }
        if let index = items.firstIndex(where: { $0.localStatus == "pending:\(input.clientRequestID)" }) {
            let localID = items[index].id
            items.removeAll { $0.messageID == receipt.assistantMessageID && $0.id != localID }
            if let pending = items.firstIndex(where: { $0.id == localID }) { items[pending].messageID = receipt.assistantMessageID; items[pending].sortKey = receipt.assistantMessageID }
        }
    }

    private func applySnapshot(_ snapshot: ChatExecutionSnapshot) async {
        guard snapshot.generation >= conversationGeneration else { return }
        if snapshot.generation != conversationGeneration {
            items.removeAll(); try? await repository?.clearPrivate(botID: bot.id)
        }
        conversationGeneration = snapshot.generation
        projection.apply(snapshot); replyTasks = projection.tasks
        detailCursor = snapshot.eventCursor // Never use snapshot.cursor in the detail domain.
        try? await activityRepository?.reconcileGeneration(botID: bot.id, generation: snapshot.generation)
        try? await activityRepository?.save(snapshot, key: "execution:\(bot.id)")
        for task in snapshot.tasks {
            if let optimistic = items.first(where: { $0.id == UUID(uuidString: task.clientRequestID) }) {
                items.removeAll { $0.messageID == task.userMessageID && $0.id != optimistic.id }
            }
            if let user = items.firstIndex(where: { $0.id == UUID(uuidString: task.clientRequestID) }) {
                items[user].messageID = task.userMessageID; items[user].sortKey = task.userMessageID; items[user].localStatus = "synced"
                await persist(items[user], status: "synced")
            }
            if let optimistic = items.first(where: { $0.localStatus == "pending:\(task.clientRequestID)" }) {
                items.removeAll { $0.messageID == task.assistantMessageID && $0.id != optimistic.id }
            }
            let index: Int
            if let existing = items.firstIndex(where: { $0.messageID == task.assistantMessageID }) { index = existing }
            else if let existing = items.firstIndex(where: { $0.localStatus == "pending:\(task.clientRequestID)" }) {
                index = existing; items[index].messageID = task.assistantMessageID
            } else {
                items.append(Item(isUser: false, text: "", messageID: task.assistantMessageID, sortKey: task.assistantMessageID)); index = items.count - 1
            }
            items[index].text = task.content // Complete snapshot replacement, never append a replay.
            items[index].traces = task.traces
            items[index].sortKey = task.assistantMessageID
            items[index].streaming = task.state == "running" || task.state == "queued"
            items[index].localStatus = task.messageStatus
            items[index].publicationRevision = task.publicationRevision
            items[index].generation = task.generation
            await persist(items[index], status: task.messageStatus)
        }
        items.sort { $0.sortKey < $1.sortKey }
        scrollTick += 1
    }
    private func startObservation() {
        detailObservation?.cancel()
        let epoch = pageEpoch
        detailObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && epoch == self.pageEpoch {
                do {
                    for try await event in self.api.chatEvents(botID: self.bot.id, afterID: self.detailCursor) {
                        guard !Task.isCancelled, epoch == self.pageEpoch else { return }
                        let json = try JSONDecoder().decode(JSONValue.self, from: event.data)
                        let eventGeneration: Int?
                        if case .number(let number) = json["generation"] { eventGeneration = Int(number) } else { eventGeneration = nil }
                        if let eventGeneration, eventGeneration < self.conversationGeneration { continue }
                        // Snapshot contains all stable partial bodies/traces and handles generation/reset fences.
                        let snapshot = try await self.api.chatExecution(botID: self.bot.id)
                        guard epoch == self.pageEpoch else { return }
                        await self.applySnapshot(snapshot)
                        if event.name == "confirmation_required" || event.name == "task_updated" { await self.refreshPendingActions(); await self.refreshMemoryStates() }
                        if event.name == "done" { await self.refreshCandidateMemories(); await self.refreshMemorySuggestions() }
                    }
                } catch { if !Task.isCancelled { self.notice = .sentence("待同步；已接收的回复会继续执行。") } }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard epoch == self.pageEpoch else { return }
                if let snapshot = try? await self.api.chatExecution(botID: self.bot.id) { await self.applySnapshot(snapshot) }
            }
        }
    }
    private func submitControl(_ control: ChatControlSubmission) async throws {
        do {
            if let waitID = control.waitID, let message = control.message {
                _ = try await api.answerChatTask(botID: bot.id, taskID: control.taskID, version: control.version, waitID: waitID, message: message, requestID: control.requestID)
            } else {
                _ = try await api.stopChatTask(botID: bot.id, taskID: control.taskID, version: control.version, requestID: control.requestID)
            }
            try await activityRepository?.removeControl(botID: bot.id, requestID: control.requestID)
        } catch let error as APIError where (400..<500).contains(error.status) && error.status != 408 {
            try await activityRepository?.removeControl(botID: bot.id, requestID: control.requestID)
            throw error
        }
    }
    func stop(_ task: ChatReplyTask) async {
        guard !controlBusy.contains(task.id), let activityRepository else { return }
        controlBusy.insert(task.id); defer { controlBusy.remove(task.id) }
        let epoch = pageEpoch
        let control = ChatControlSubmission(generation: task.generation, taskID: task.id, version: task.version)
        do { try await activityRepository.saveControl(control, botID: bot.id); try await submitControl(control); if epoch == pageEpoch { await recoverExecution() } }
        catch {
            if epoch == pageEpoch {
                if let message = (error as? APIError)?.message, !message.isEmpty { notice = .sentence(message) }
                else { notice = .sentence("停止结果待确认，恢复网络后会继续核对。") }
                scheduleRecovery()
            }
        }
    }
    func send(_ text: String, attachment: Attachment? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || attachment != nil, !sending else { return }
        sending = true; defer { sending = false }
        notice = nil
        if let id = selectedWaitTaskID, let task = replyTasks.first(where: { $0.id == id && $0.state == "awaiting_user" }), let waitID = task.waitID {
            do {
                guard let activityRepository else { notice = .sentence("本地发送记录尚未准备好，请稍后重试。"); return }
                let control = ChatControlSubmission(generation: task.generation, taskID: task.id, version: task.version, waitID: waitID, message: trimmed)
                try await activityRepository.saveControl(control, botID: bot.id)
                try await submitControl(control)
                selectedWaitTaskID = nil; await saveDraft(""); await load()
            } catch { notice = .fromAction(error, message: UserFacingError.message(for: error)); scheduleRecovery() }
            return
        }
        guard let activityRepository else { notice = .sentence("本地发送记录尚未准备好，请稍后重试。"); return }
        let epoch = pageEpoch
        let input = ChatInputRequest(message: trimmed, attachmentIDs: attachment.map { [$0.id] } ?? [], expectedGeneration: conversationGeneration)
        do { try await activityRepository.savePending(input, botID: bot.id) }
        catch { notice = .fromAction(error, message: UserFacingError.message(for: error)); return }
        let userID = UUID(uuidString: input.clientRequestID) ?? UUID()
        let sort = (items.last?.sortKey ?? 0) + 1
        items.append(Item(id: userID, isUser: true, text: trimmed, attachments: attachment.map { [$0] } ?? [], sortKey: sort, localStatus: "sending"))
        items.append(Item(id: pendingAssistantID(input.clientRequestID), isUser: false, text: "正在发送…", sortKey: sort + 1, localStatus: "pending:\(input.clientRequestID)"))
        await persist(items[items.count - 2], status: "sending")
        await persist(items[items.count - 1], status: "pending:\(input.clientRequestID)")
        await saveDraft(""); scrollTick += 1
        do {
            let receipt = try await api.submitChatInput(botID: bot.id, input: input)
            let fresh = try await api.chatExecution(botID: bot.id)
            guard epoch == pageEpoch, !Task.isCancelled else { return }
            if receipt.generation == fresh.generation { bindReceipt(receipt, input: input) }
            await applySnapshot(fresh)
            try await activityRepository.removePending(botID: bot.id, requestID: input.clientRequestID)
            startObservation()
        } catch {
            guard epoch == pageEpoch else { return }
            if let error = error as? APIError, (400..<500).contains(error.status), error.status != 408 {
                try? await activityRepository.removePending(botID: bot.id, requestID: input.clientRequestID)
                notice = .sentence(error.message)
            } else { notice = .sentence("发送结果待确认，恢复网络后会用原请求核对。"); scheduleRecovery() }
        }
    }
}
