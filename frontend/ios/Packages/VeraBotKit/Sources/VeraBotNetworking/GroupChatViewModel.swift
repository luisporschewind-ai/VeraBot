import Foundation
import Observation
import VeraBotCore

@MainActor @Observable
public final class GroupChatViewModel {
    public private(set) var group: ChatGroup
    public private(set) var state: GroupChatState
    public var draft = ""
    public var errorMessage: String?
    public private(set) var loading = false
    public private(set) var nextBeforeID: Int?
    public private(set) var confirmingStop = false
    public var preferredBotID: Int?
    public var busy: Bool { task != nil || state.status == .running }
    @ObservationIgnored public let api: any GroupChatAPI
    @ObservationIgnored private let sessionIsCurrent: @MainActor @Sendable () -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var epoch = 0

    public init(group: ChatGroup, api: any GroupChatAPI, sessionIsCurrent: @escaping @MainActor @Sendable () -> Bool = { true }) {
        self.group = group; self.api = api; self.sessionIsCurrent = sessionIsCurrent
        state = GroupChatState(groupID: group.id)
    }
    private func valid(_ stamp: Int) throws {
        try Task.checkCancellation()
        guard stamp == epoch, sessionIsCurrent() else { throw CancellationError() }
    }
    public func load() async {
        let stamp = epoch; loading = true
        defer { if stamp == epoch { loading = false } }
        do {
            try valid(stamp)
            let updated = try await api.group(id: group.id)
            let page = try await api.groupMessages(groupID: group.id, beforeID: nil)
            try valid(stamp)
            group = updated; state.messages = page.messages; nextBeforeID = page.nextBeforeID
            errorMessage = nil
            if let tid = updated.activeTurnID ?? page.messages.last?.turnID {
                let turn = try await api.groupTurn(groupID: group.id, turnID: tid)
                try valid(stamp); await reconcileRestoredTurn(turn, stamp: stamp)
                try valid(stamp)
            } else { state = GroupChatState(groupID: group.id) }
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
            let page = try await api.groupMessages(groupID: group.id, beforeID: cursor)
            try valid(stamp)
            let ids = Set(state.messages.map(\.id))
            state.messages.insert(contentsOf: page.messages.filter { !ids.contains($0.id) }, at: 0)
            nextBeforeID = page.nextBeforeID
        } catch is CancellationError {} catch { if stamp == epoch && sessionIsCurrent() { errorMessage = friendly(error) } }
    }
    public func send(text: String, mode: GroupChatMode, targetBotID: Int?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !loading, !group.readOnly, !text.isEmpty, text.count <= 2000, sessionIsCurrent() else { return }
        draft = text
        let request = GroupChatRequest(message: text, mode: mode, targetBotID: mode == .round ? nil : targetBotID)
        start(api.groupChatStream(groupID: group.id, request: request), preferred: mode == .single ? targetBotID : nil, clearDraft: true)
    }
    public func retry(messageID: Int) {
        guard !busy, sessionIsCurrent() else { return }
        start(api.retryGroupMessage(groupID: group.id, messageID: messageID, requestID: UUID()), preferred: nil, clearDraft: false)
    }
    private func start(_ stream: AsyncThrowingStream<GroupChatEvent, Error>, preferred: Int?, clearDraft: Bool) {
        epoch += 1; let stamp = epoch; errorMessage = nil
        task = Task {
            defer { if stamp == epoch { task = nil } }
            do {
                for try await event in stream {
                    try valid(stamp)
                    GroupChatReducer.apply(event, to: &state)
                    if case .error(_, let message, _) = event.payload { errorMessage = message }
                    if case .turnStart = event.payload {
                        if clearDraft { draft = "" }
                        if let preferred { preferredBotID = preferred }
                    }
                }
                if let updated = try? await api.group(id: group.id) {
                    try valid(stamp); group = updated
                    if !group.members.contains(where: { $0.available && $0.botID == preferredBotID }) {
                        preferredBotID = group.defaultBotID
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
        try valid(stamp); state = GroupChatState(groupID: group.id); nextBeforeID = nil
    }
    public func delete() async throws {
        let stamp = epoch; try valid(stamp)
        _ = try await api.deleteGroup(id: group.id); try valid(stamp)
    }
    private func friendly(_ error: Error) -> String {
        if let api = error as? APIError, api.status == 409 { return "讨论还在进行，请先停止后再操作。" }
        if let api = error as? APIError, api.status == 429 { return "今日额度已用完，请稍后继续。" }
        return "伙伴们暂时没连上，请重新加载后再试。"
    }
}
