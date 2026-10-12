import Foundation
import Observation
import VeraBotCore
import VeraBotNetworking

@MainActor @Observable
public final class GroupChatViewModel {
    public private(set) var group: ChatGroup
    public private(set) var state: GroupChatState
    public var draft = ""
    public var errorMessage: String?
    public private(set) var loading = false
    public private(set) var historyIncomplete = false
    public private(set) var nextBeforeID: Int?
    public private(set) var confirmingStop = false
    public var preferredBotID: Int?
    public var busy: Bool { task != nil || state.status == .running }
    @ObservationIgnored public let api: any GroupChatAPI
    @ObservationIgnored private let repository: ConversationRepository?
    @ObservationIgnored private let sessionIsCurrent: @MainActor @Sendable () -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var epoch = 0

    public init(group: ChatGroup, api: any GroupChatAPI, repository: ConversationRepository? = nil,
                sessionIsCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) {
        self.group = group; self.api = api; self.repository = repository; self.sessionIsCurrent = sessionIsCurrent
        state = GroupChatState(groupID: group.id)
    }
    private func valid(_ stamp: Int) throws {
        try Task.checkCancellation()
        guard stamp == epoch, sessionIsCurrent() else { throw CancellationError() }
    }
    public func load() async {
        let stamp = epoch; loading = true
        defer { if stamp == epoch { loading = false } }
        if let repository {
            do {
                if let cached = try await repository.cachedGroup(id: group.id) { group = cached }
                let local = try await repository.groupMessages(groupID: group.id, limit: 101)
                state.messages = local.suffix(100).map(\.value)
                for index in state.messages.indices where state.messages[index].status == .streaming {
                    state.messages[index].status = .interrupted
                    try? await repository.saveGroupMessage(state.messages[index], groupID: group.id, status: "interrupted")
                }
                nextBeforeID = local.count > 100 ? state.messages.first?.id : nil
                draft = try await repository.draft(kind: .group, id: group.id)
                historyIncomplete = !((try? await repository.isHistoryComplete(kind: .group, id: group.id)) ?? false)
            } catch { errorMessage = "本地群聊历史暂时无法读取。" }
        }
        do {
            try valid(stamp)
            let updated = try await api.group(id: group.id)
            let page = try await api.groupMessages(groupID: group.id, beforeID: nil)
            try valid(stamp)
            group = updated
            if repository == nil { state.messages = page.messages; nextBeforeID = page.nextBeforeID }
            if let repository {
                for message in page.messages { try? await repository.saveGroupMessage(message, groupID: group.id, status: message.status.rawValue) }
                try? await repository.syncGroup(groupID: group.id)
                let local = try await repository.groupMessages(groupID: group.id, limit: 101)
                state.messages = local.suffix(100).map(\.value)
                nextBeforeID = local.count > 100 ? state.messages.first?.id : nil
                historyIncomplete = !((try? await repository.isHistoryComplete(kind: .group, id: group.id)) ?? false)
            }
            errorMessage = nil
            if let tid = updated.activeTurnID ?? page.messages.last?.turnID {
                let turn = try await api.groupTurn(groupID: group.id, turnID: tid)
                try valid(stamp); await reconcileRestoredTurn(turn, stamp: stamp)
                try valid(stamp)
            } else if repository == nil { state = GroupChatState(groupID: group.id) }
            if !group.members.contains(where: { $0.available && $0.botID == preferredBotID }) {
                let previous = preferredBotID; preferredBotID = group.defaultBotID
                if previous != nil && !group.readOnly { errorMessage = "原回应者已不可用，已切换到其他伙伴。" }
            }
        } catch is CancellationError {} catch { if stamp == epoch && sessionIsCurrent() { errorMessage = friendly(error) } }
    }
    public func loadOlder() async {
        guard let cursor = nextBeforeID, !loading else { return }
        let stamp = epoch; loading = true
        defer { if stamp == epoch { loading = false } }
        do {
            if let repository {
                let page = try await repository.groupMessages(groupID: group.id, before: cursor, limit: 101)
                try valid(stamp)
                let older = page.suffix(100).map(\.value)
                state.messages.insert(contentsOf: older.filter { message in !state.messages.contains(where: { $0.id == message.id }) }, at: 0)
                nextBeforeID = page.count > 100 ? state.messages.first?.id : nil
                return
            }
            let page = try await api.groupMessages(groupID: group.id, beforeID: cursor)
            try valid(stamp)
            let ids = Set(state.messages.map(\.id))
            state.messages.insert(contentsOf: page.messages.filter { !ids.contains($0.id) }, at: 0)
            nextBeforeID = page.nextBeforeID
        } catch is CancellationError {} catch { if stamp == epoch && sessionIsCurrent() { errorMessage = friendly(error) } }
    }
    public func send(text: String, mode: GroupChatMode = .auto, targetBotID: Int? = nil, attachmentIDs: [String] = []) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !loading, !group.readOnly, (!text.isEmpty || !attachmentIDs.isEmpty), text.count <= 2000, sessionIsCurrent() else { return }
        draft = text
        let request = GroupChatRequest(message: text, mode: mode, targetBotID: mode == .round || mode == .auto ? nil : targetBotID,
                                       attachmentIDs: attachmentIDs)
        start(api.groupChatStream(groupID: group.id, request: request), preferred: mode == .single ? targetBotID : nil,
              clearDraft: true, persistDraftBeforeStream: text)
    }
    public func retry(messageID: Int) {
        guard !busy, sessionIsCurrent() else { return }
        start(api.retryGroupMessage(groupID: group.id, messageID: messageID, requestID: UUID()), preferred: nil, clearDraft: false)
    }
    private func start(_ stream: AsyncThrowingStream<GroupChatEvent, Error>, preferred: Int?, clearDraft: Bool,
                       persistDraftBeforeStream: String? = nil) {
        epoch += 1; let stamp = epoch; errorMessage = nil
        task = Task {
            defer { if stamp == epoch { task = nil } }
            do {
                if let persistDraftBeforeStream {
                    try? await repository?.saveDraft(persistDraftBeforeStream, kind: .group, id: group.id)
                }
                for try await event in stream {
                    try valid(stamp)
                    GroupChatReducer.apply(event, to: &state)
                    for message in state.messages { try? await repository?.saveGroupMessage(message, groupID: group.id, status: message.status.rawValue) }
                    // Member-scoped failures already render on their message bubble with a retry action.
                    // Reserve the page-level notice for errors that affect the whole turn.
                    if case .error(_, let message, let messageID) = event.payload, messageID == nil {
                        errorMessage = message
                    }
                    if case .turnStart = event.payload {
                        if clearDraft { draft = ""; try? await repository?.saveDraft("", kind: .group, id: group.id) }
                        if let preferred { preferredBotID = preferred }
                    }
                }
                if let updated = try? await api.group(id: group.id) {
                    try valid(stamp); group = updated
                    if let preferredBotID,
                       !group.members.contains(where: { $0.available && $0.botID == preferredBotID }) {
                        self.preferredBotID = group.defaultBotID
                        if errorMessage == nil && !group.readOnly { errorMessage = "原回应者已不可用，已切换到其他伙伴。" }
                    }
                }
            } catch let existing as GroupRequestExists {
                await reconcileRestoredTurn(existing.turn, stamp: stamp)
            } catch is CancellationError {} catch {
                guard stamp == epoch, sessionIsCurrent() else { return }
                errorMessage = friendly(error)
                if let conflict = error as? APIError, let tid = conflict.turnID,
                   let turn = try? await api.groupTurn(groupID: group.id, turnID: tid) {
                    await reconcileRestoredTurn(turn, stamp: stamp)
                } else if state.activeTurnID != nil { await stop() }
            }
        }
    }
    private func reconcileRestoredTurn(_ initial: GroupTurn, stamp: Int) async {
        do {
            try valid(stamp)
            var turn = initial
            GroupChatReducer.restore(turn, to: &state)
            for _ in 0..<40 {
                if turn.status != .running { return }
                try await Task.sleep(for: .milliseconds(250))
                try valid(stamp)
                turn = try await api.groupTurn(groupID: group.id, turnID: turn.id)
                try valid(stamp)
                GroupChatReducer.restore(turn, to: &state)
            }
            if turn.status == .running { errorMessage = "讨论仍在进行，请稍后重新加载查看结果。" }
        } catch is CancellationError {} catch {
            if stamp == epoch && sessionIsCurrent() { errorMessage = friendly(error) }
        }
    }
    public func stop() async {
        guard let tid = state.activeTurnID, state.status == .running, sessionIsCurrent() else { return }
        let stamp = epoch; confirmingStop = true
        defer { if stamp == epoch { confirmingStop = false } }
        do {
            try valid(stamp)
            var turn = try await api.stopGroupTurn(groupID: group.id, turnID: tid)
            for _ in 0..<40 {
                try valid(stamp)
                if turn.status != .running { break }
                try await Task.sleep(for: .milliseconds(250))
                turn = try await api.groupTurn(groupID: group.id, turnID: tid)
            }
            try valid(stamp); GroupChatReducer.restore(turn, to: &state)
            if turn.status == .running { errorMessage = "正在确认讨论是否已停止，请稍后重新加载。" }
        } catch is CancellationError {} catch { if stamp == epoch && sessionIsCurrent() { errorMessage = "暂时无法确认是否已停止，请恢复连接后重新加载。" } }
    }
    public func leave() {
        let tid = state.status == .running ? state.activeTurnID : nil
        epoch += 1; task?.cancel(); task = nil; loading = false
        if let tid, sessionIsCurrent() {
            Task { if sessionIsCurrent() { _ = try? await api.stopGroupTurn(groupID: group.id, turnID: tid) } }
        }
    }
    public func update(name: String? = nil, defaultBotID: Int? = nil) async throws {
        let stamp = epoch; try valid(stamp)
        let updated = try await api.updateGroup(id: group.id, request: GroupUpdateRequest(name: name, defaultBotID: defaultBotID))
        try valid(stamp)
        group = updated
        if defaultBotID != nil {
            preferredBotID = updated.defaultBotID
        }
    }
    public func clear() async throws {
        let stamp = epoch; try valid(stamp)
        _ = try await api.clearGroupMessages(groupID: group.id)
        try valid(stamp)
        try? await repository?.clearGroup(groupID: group.id)
        try valid(stamp); state = GroupChatState(groupID: group.id); nextBeforeID = nil
    }
    public func delete() async throws {
        let stamp = epoch; try valid(stamp)
        _ = try await api.deleteGroup(id: group.id); try valid(stamp)
        try? await repository?.removeGroup(groupID: group.id)
    }
    private func friendly(_ error: Error) -> String {
        if let api = error as? APIError, api.status == 409 { return "讨论还在进行，请先停止后再操作。" }
        if let api = error as? APIError, api.status == 429 { return "今日额度已用完，请稍后继续。" }
        return "伙伴们暂时没连上，请重新加载后再试。"
    }
}
