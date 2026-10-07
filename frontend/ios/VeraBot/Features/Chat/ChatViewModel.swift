import SwiftUI
import VeraBotCore
import VeraBotNetworking

@MainActor
@Observable
final class ChatViewModel {
    struct Item: Identifiable {
        let id = UUID()
        let isUser: Bool
        var text: String
        var traces: [ToolTrace] = []
        var streaming = false
        var messageID: Int?
        var attachments: [Attachment] = []   // 用户消息里的图片（v12）
        var feedback: MessageFeedback?       // assistant 消息的 👍 / 👎（M2）
    }

    var bot: Bot
    let api: any VeraBotAPI   // 气泡里的图片也用它下载（鉴权、no-store）
    var items: [Item] = []
    var sending = false
    var errorText: String?
    var scrollTick = 0
    /// 对话中记忆确认卡片的服务器状态（memory_id → 最新 Memory；nil 值 = 已不存在）
    var memoryStates: [Int: Memory?] = [:]
    /// 本机刚处理过、服务器上已删除的提议（如「忘掉」确认后提议本身被删除）：memory_id → 结果文案
    var memoryOutcomes: [Int: String] = [:]
    var memoryBusy: Set<Int> = []
    var memoryConfirmTick = 0   // 触感反馈触发器：确认记住 +1
    /// MCP M3 确认卡片：action_id → 最新 PendingAction
    var actionStates: [Int: PendingAction] = [:]
    var actionBusy: Set<Int> = []
    /// 执行状态机与头像计时（对话页导航栏读取 `executionState`）。
    private var playback = ExecutionAvatarController()
    var executionState: ExecutionState { playback.state }
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

    init(bot: Bot, api: any VeraBotAPI) {
        self.bot = bot
        self.api = api
    }

    func load() async {
        do {
            let r = try await api.messages(botID: bot.id)
            items = r.messages.map {
                Item(isUser: $0.role == "user", text: $0.content, traces: $0.traces ?? [], messageID: $0.id,
                     attachments: $0.attachments, feedback: $0.feedback)
            }
            if items.isEmpty {
                items = [Item(isUser: false, text: "你好，我是 **\(bot.name)**。试试：「石家庄天气怎么样」「明早 9 点提醒我开会」「记住我不吃香菜」")]
            }
            scrollTick += 1
        } catch {
            errorText = error.localizedDescription
        }
        await refreshMemoryStates()
        await refreshPendingActions()
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
            errorText = e.message
        } catch let e as APIError {
            errorText = e.message
            if e.status == 409, let a = try? await api.pendingAction(id: id) {
                actionStates[id] = a
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    func cancelAction(_ id: Int) async {
        actionBusy.insert(id)
        defer { actionBusy.remove(id) }
        do {
            actionStates[id] = try await api.cancelPendingAction(id: id)
        } catch let e as APIError {
            errorText = e.message
            if e.status == 409 || e.status == 410, let a = try? await api.pendingAction(id: id) {
                actionStates[id] = a
            }
        } catch {
            errorText = error.localizedDescription
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
            errorText = error.localizedDescription
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
            errorText = error.localizedDescription
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
            errorText = error.localizedDescription
        }
    }

    /// 清空对话；includeMemories = true 时同时删除该 Bot 的「本 Bot 记忆」。对话摘要总会删掉，已确认的记忆默认保留。
    func clear(includeMemories: Bool = false) async {
        _ = try? await api.clearMessages(botID: bot.id, includeMemories: includeMemories)
        memoryStates = [:]
        memoryOutcomes = [:]
        actionStates = [:]
        feed(.reset)
        await load()
    }

    /// 删除单条消息：只对已落库（有 messageID）且不在流式输出中的条目生效；成功后从列表移除，失败按其他错误一样显示在 errorText。
    func delete(_ item: Item) async {
        guard let mid = item.messageID, !item.streaming else { return }
        do {
            _ = try await api.deleteMessage(botID: bot.id, messageID: mid)
            items.removeAll { $0.messageID == mid }
        } catch let e as APIError where e.status == 404 {
            items.removeAll { $0.messageID == mid }   // 服务器上已不存在（如另一台设备已删除），以服务器为准
        } catch {
            errorText = error.localizedDescription
        }
    }

    func send(_ text: String, attachment: Attachment? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || attachment != nil, !sending else { return }
        sending = true
        errorText = nil
        feed(.sent)
        let images = attachment.map { [$0] } ?? []
        items.append(Item(isUser: true, text: trimmed, attachments: images))
        items.append(Item(isUser: false, text: "", streaming: true))
        let idx = items.count - 1
        scrollTick += 1
        do {
            for try await event in api.chatStream(botID: bot.id, message: trimmed, attachmentIDs: images.map(\.id)) {
                feed(event.executionEvent)
                switch event {
                case .delta(let t):
                    items[idx].text += t
                case .toolStart(let trace):
                    items[idx].traces.append(trace)
                case .toolResult(let trace):
                    if let i = items[idx].traces.firstIndex(where: { $0.id == trace.id }) {
                        items[idx].traces[i] = trace
                    } else {
                        items[idx].traces.append(trace)
                    }
                    if let pending = trace.pendingConfirmation {
                        actionStates[pending.actionId] = pending.asPending()
                    }
                    if ["create_reminder", "manage_reminder", "list_reminders"].contains(trace.name) {
                        NotificationCenter.default.post(name: .verabotRemindersChanged, object: nil)
                    }
                case .confirmationRequired(let req):
                    actionStates[req.actionId] = req.asPending()
                case .error(let msg):
                    appendError(msg, at: idx)
                case .done(let d):
                    // 落库后的 id：刚收到的回复与刚发出的用户消息（idx - 1）都能立即长按删除；旧后端不发 user_message_id
                    items[idx].messageID = d.messageID
                    if let uid = d.userMessageID { items[idx - 1].messageID = uid }
                case .status:
                    break   // 只驱动导航栏头像；消息正文不显示 status
                case .notification:
                    NotificationCenter.default.post(name: .verabotRemindersChanged, object: nil)
                }
                scrollTick += 1
            }
        } catch let e as APIError where e.status == 429 {
            let msg = "今日额度已用完，请明天再试（可在「设置 › 用量」查看今日用量）"
            feed(.error(msg))
            appendError(msg, at: idx)
        } catch {
            feed(.error(error.localizedDescription))
            appendError(error.localizedDescription, at: idx)
        }
        feed(.streamEnded)
        if items[idx].text.isEmpty && items[idx].traces.isEmpty { items[idx].text = "（无回复）" }
        items[idx].streaming = false
        sending = false
        scrollTick += 1
        if items[idx].traces.contains(where: { $0.memoryProposal?.isCard == true }) {
            await refreshMemoryStates()
        }
        if items[idx].traces.contains(where: { $0.pendingConfirmation != nil }) {
            await refreshPendingActions()
        }
    }
}
