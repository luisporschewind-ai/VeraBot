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
    public private(set) var loadingOlder = false
    public private(set) var historyIncomplete = false
    public private(set) var nextBeforeID: Int?
    public private(set) var confirmingStop = false
    public private(set) var execution = GroupExecutionViewState()
    public private(set) var executionSyncPending = false
    public private(set) var sending = false
    public private(set) var pendingInput: GroupInputRequest?
    public var hasUnconfirmedInput: Bool {pendingInput != nil}
    public var busy: Bool {sending || execution.snapshot.task.map {$0.state == .queued || $0.state == .running} == true}
    public var canStop: Bool {execution.snapshot.task?.state.canStop == true}
    @ObservationIgnored public let api: any GroupChatAPI
    @ObservationIgnored private let repository: ConversationRepository?
    @ObservationIgnored private let sessionIsCurrent: @MainActor @Sendable () -> Bool
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var observerTask: Task<Void,Never>?
    @ObservationIgnored private var epoch = 0

    public init(group: ChatGroup, api: any GroupChatAPI, repository: ConversationRepository? = nil,
                sessionIsCurrent: @escaping @MainActor @Sendable () -> Bool = {true}) {
        self.group = group; self.api = api; self.repository = repository; self.sessionIsCurrent = sessionIsCurrent
        state = GroupChatState(groupID:group.id)
    }
    private func valid(_ stamp: Int) throws {
        try Task.checkCancellation()
        guard stamp == epoch,sessionIsCurrent() else {throw CancellationError()}
    }
    public func saveDraft(_ text: String) async {
        guard !Task.isCancelled,sessionIsCurrent() else {return}
        try? await repository?.saveDraft(text,kind:.group,id:group.id)
    }
    private func displayExecution() {
        state.messages = execution.messages
        switch execution.snapshot.task?.state {
        case .running,.queued:state.status = .running
        case .awaitingUser:state.status = .partial
        case .completed:state.status = .completed
        case .stopped:state.status = .stopped
        case .failed:state.status = .failed
        case .interrupted:state.status = .interrupted
        case nil:state.status = nil
        }
        state.activeTurnID = state.messages.last(where:{$0.status == .streaming})?.turnID
    }
    private func acceptSnapshot(_ snapshot: GroupExecutionSnapshot) {
        var messages = state.messages
        for message in snapshot.messages ?? [] {
            if let index = messages.firstIndex(where:{$0.id == message.id}) {messages[index] = message}
            else {messages.append(message)}
        }
        execution.snapshot = snapshot
        execution.snapshot.messages = nil
        execution.messages = messages.sorted {$0.id < $1.id}
        executionSyncPending = false
        displayExecution()
    }
    private func persistExecution(_ stamp: Int) async throws {
        try valid(stamp)
        try await repository?.saveGroupExecution(execution.snapshot,messages:execution.messages,groupID:group.id)
        try valid(stamp)
    }
    public func load(localReady: @MainActor () async -> Void = {}) async {
        let stamp = epoch;loading = true
        defer {if stamp == epoch {loading = false}}
        do {
            if let repository {
                let cached = try await repository.cachedGroup(id:group.id)
                try valid(stamp);if let cached {group = cached}
                let visibleLimit = max(100, state.messages.count)
                let local = try await repository.groupMessages(groupID:group.id,limit:visibleLimit + 1)
                try valid(stamp);state.messages = local.suffix(visibleLimit).map(\.value)
                nextBeforeID = local.count > visibleLimit ? state.messages.first?.id : nil
                let savedDraft = try await repository.draft(kind:.group,id:group.id)
                try valid(stamp);draft = savedDraft
                let pending = try await repository.pendingGroupInput(groupID:group.id)
                try valid(stamp);pendingInput = pending
                if let cached = try await repository.groupExecutionSnapshot(groupID:group.id) {
                    try valid(stamp);execution.snapshot = cached;executionSyncPending = true
                }
            }
            execution.messages = state.messages
            if let repository {
                historyIncomplete = !(try await repository.isHistoryComplete(kind: .group, id: group.id))
            }
            displayExecution()
            try valid(stamp)
            await localReady()
            try valid(stamp)
            let updated = try await api.group(id:group.id)
            try valid(stamp);group = updated
            if let repository {
                try await repository.syncGroup(groupID:group.id)
                let visibleLimit = max(100, state.messages.count)
                let local = try await repository.groupMessages(groupID:group.id,limit:visibleLimit + 1)
                try valid(stamp);state.messages = local.suffix(visibleLimit).map(\.value)
                nextBeforeID = local.count > visibleLimit ? state.messages.first?.id : nil
                historyIncomplete = !((try? await repository.isHistoryComplete(kind:.group,id:group.id)) ?? false)
            } else {
                let page = try await api.groupMessages(groupID:group.id,beforeID:nil)
                try valid(stamp);state.messages = page.messages;nextBeforeID = page.nextBeforeID
            }
            let snapshot = try await api.groupExecution(groupID:group.id)
            try valid(stamp);acceptSnapshot(snapshot);try await persistExecution(stamp)
            errorMessage = nil
            if pendingInput != nil {
                sending = true
                defer {if stamp == epoch {sending = false}}
                try await reconcilePending(stamp:stamp,lookupFirst:true)
            }
            observeExecution(stamp:stamp)
        } catch is CancellationError {} catch {if stamp == epoch && sessionIsCurrent() {errorMessage = friendly(error)}}
    }
    public func loadOlder() async {
        guard let cursor = nextBeforeID,!loadingOlder,(!loading || repository != nil) else {return}
        let stamp = epoch;loadingOlder = true
        defer {if stamp == epoch {loadingOlder = false}}
        do {
            let older: [GroupMessage]
            if let repository {
                let page = try await repository.groupMessages(groupID:group.id,before:cursor,limit:101)
                older = page.suffix(100).map(\.value)
                try valid(stamp);nextBeforeID = page.count > 100 ? older.first?.id : nil
            } else {
                let page = try await api.groupMessages(groupID:group.id,beforeID:cursor)
                older = page.messages;try valid(stamp);nextBeforeID = page.nextBeforeID
            }
            let ids = Set(state.messages.map(\.id))
            state.messages.insert(contentsOf:older.filter {!ids.contains($0.id)},at:0)
            execution.messages = state.messages
        } catch is CancellationError {} catch {if stamp == epoch && sessionIsCurrent() {errorMessage = friendly(error)}}
    }
    public func send(text: String,targetMemberIDs: [Int] = [],everyone: Bool = false,replyToMessageID: Int? = nil,attachmentIDs: [String] = []) {
        let text = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !loading,!sending,!group.readOnly,(!text.isEmpty || !attachmentIDs.isEmpty),text.count <= 2000,sessionIsCurrent() else {return}
        if pendingInput != nil {recoverPendingSubmission();return}
        let active = execution.snapshot.task.flatMap {$0.state.canStop ? $0 : nil}
        pendingInput = .init(message:text,targetMemberIDs:targetMemberIDs,everyone:everyone,replyToMessageID:replyToMessageID,
                             attachmentIDs:attachmentIDs,expectedTaskID:active?.id,expectedVersion:active?.version,
                             clarificationID:active?.state == .awaitingUser ? execution.snapshot.clarification?.id : nil)
        draft = text
        beginSubmission(lookupFirst:false)
    }
    public func recoverPendingSubmission() {
        guard !sending,pendingInput != nil,sessionIsCurrent() else {return}
        beginSubmission(lookupFirst:true)
    }
    private func beginSubmission(lookupFirst: Bool) {
        let stamp = epoch;sending = true;errorMessage = nil
        task = Task {
            defer {if stamp == epoch {task = nil;sending = false}}
            do {
                guard let request = pendingInput else {return}
                try await repository?.savePendingGroupInput(request,groupID:group.id)
                try await repository?.saveDraft(request.message,kind:.group,id:group.id)
                try valid(stamp)
                try await reconcilePending(stamp:stamp,lookupFirst:lookupFirst)
                observeExecution(stamp:stamp)
            } catch is CancellationError {} catch {if stamp == epoch && sessionIsCurrent() {errorMessage = friendly(error)}}
        }
    }
    private func reconcilePending(stamp: Int,lookupFirst: Bool) async throws {
        guard let request = pendingInput else {return}
        var receipt: GroupInputReceipt
        do {
            if lookupFirst {
                do {receipt = try await api.groupInputReceipt(groupID:group.id,requestID:request.clientRequestID)}
                catch let error as APIError where error.status == 404 {
                    try valid(stamp);receipt = try await api.submitGroupInput(groupID:group.id,request:request)
                }
            } else {
                do {receipt = try await api.submitGroupInput(groupID:group.id,request:request)}
                catch let error as APIError where error.status >= 400 && error.status < 500 {throw error}
                catch {
                    try valid(stamp)
                    do {receipt = try await api.groupInputReceipt(groupID:group.id,requestID:request.clientRequestID)}
                    catch let error as APIError where error.status == 404 {
                        try valid(stamp);receipt = try await api.submitGroupInput(groupID:group.id,request:request)
                    }
                }
            }
            try valid(stamp)
            execution.snapshot.task = receipt.task
            // Receipt points before acceptance: replay every message not yet applied.
            execution.snapshot.eventCursor = max(execution.snapshot.eventCursor,receipt.eventCursor)
            pendingInput = nil
            if draft.trimmingCharacters(in:.whitespacesAndNewlines) == request.message {draft = ""}
            try await repository?.savePendingGroupInput(nil,groupID:group.id)
            try await repository?.saveDraft(draft,kind:.group,id:group.id)
            try await persistExecution(stamp)
        } catch let error as APIError where error.status >= 400 && error.status < 500 {
            try valid(stamp)
            pendingInput = nil
            try await repository?.savePendingGroupInput(nil,groupID:group.id)
            if error.status == 409 {
                let snapshot = try await api.groupExecution(groupID:group.id)
                try valid(stamp);acceptSnapshot(snapshot);try await persistExecution(stamp)
                errorMessage = "任务已在另一处更新，已同步最新进度。请根据当前问题继续。"
                observeExecution(stamp:stamp)
                return
            }
            throw error
        }
    }
    public func stop() async {
        guard let active = execution.snapshot.task,active.state.canStop,sessionIsCurrent() else {return}
        let stamp = epoch;confirmingStop = true
        defer {if stamp == epoch {confirmingStop = false}}
        do {
            let updated = try await api.stopGroupTask(groupID:group.id,taskID:active.id,expectedVersion:active.version,requestID:UUID())
            try valid(stamp);execution.snapshot.task = updated;execution.snapshot.clarification = nil
            displayExecution();try await persistExecution(stamp);observeExecution(stamp:stamp)
        } catch is CancellationError {} catch {if stamp == epoch && sessionIsCurrent() {errorMessage = friendly(error)}}
    }
    public func canRetry(messageID: Int) -> Bool {
        guard !busy,!hasUnconfirmedInput,let message=state.messages.first(where:{$0.id == messageID}),
              message.presentsIncompleteReply,
              [.failed,.interrupted].contains(message.status),message.taskID != nil,message.taskVersion != nil else {return false}
        return true
    }
    public func resume() {command(messageID:nil)}
    public func retry(messageID: Int) {command(messageID:messageID)}
    private func command(messageID: Int?) {
        guard !busy,!hasUnconfirmedInput,sessionIsCurrent() else {return}
        let active = execution.snapshot.task
        let message = messageID.flatMap {id in state.messages.first(where:{$0.id == id})}
        if let messageID {guard canRetry(messageID:messageID) else {return}}
        else {guard active?.state.canResume == true else {return}}
        let stamp = epoch;sending = true
        task = Task {
            defer {if stamp == epoch {task = nil;sending = false}}
            do {
                let updated: GroupTask
                if let messageID {updated = try await api.retryGroupTaskMessage(groupID:group.id,messageID:messageID,expectedVersion:message?.taskID == active?.id ? active!.version : message!.taskVersion!,requestID:UUID())}
                else {updated = try await api.resumeGroupTask(groupID:group.id,taskID:active!.id,expectedVersion:active!.version,message:"",requestID:UUID())}
                try valid(stamp);execution.snapshot.task = updated;observeExecution(stamp:stamp)
            } catch is CancellationError {} catch {if stamp == epoch && sessionIsCurrent() {errorMessage = friendly(error)}}
        }
    }
    public func leave() {
        epoch += 1;task?.cancel();task = nil;observerTask?.cancel();observerTask = nil
        loading = false;loadingOlder = false;sending = false
    }
    public func update(name: String? = nil) async throws {
        let stamp = epoch;let updated = try await api.updateGroup(id:group.id,request:.init(name:name))
        try valid(stamp);group = updated
        try await repository?.saveGroup(updated)
    }
    /// Single add; does **not** mutate `group` — caller applies with animation.
    @discardableResult
    public func addMember(botID: Int) async throws -> ChatGroup {
        let stamp = epoch
        let updated = try await api.addGroupMember(groupID: group.id, botID: botID)
        try valid(stamp)
        try await repository?.saveGroup(updated)
        return updated
    }

    /// Sequential POSTs. On partial failure, `group` in the result includes successful adds; `failure` is set.
    public func addMembers(botIDs: [Int]) async -> (group: ChatGroup, addedCount: Int, failure: Error?) {
        var latest = group
        var added = 0
        for botID in botIDs {
            do {
                let stamp = epoch
                let updated = try await api.addGroupMember(groupID: group.id, botID: botID)
                try valid(stamp)
                latest = updated
                added += 1
                try await repository?.saveGroup(updated)
            } catch {
                return (latest, added, error)
            }
        }
        return (latest, added, nil)
    }

    /// Calls the remove API and persists cache, but does **not** mutate `group`.
    /// The view applies the result inside `withAnimation` so the List can animate the row out.
    @discardableResult
    public func removeMember(memberID: Int) async throws -> ChatGroup {
        let stamp = epoch
        let updated = try await api.removeGroupMember(groupID: group.id, memberID: memberID)
        try valid(stamp)
        try await repository?.saveGroup(updated)
        return updated
    }

    public func applyGroup(_ updated: ChatGroup) {
        group = updated
    }
    public func clear() async throws {
        leave();let stamp = epoch
        _ = try await api.clearGroupMessages(groupID:group.id);try valid(stamp)
        try await repository?.clearGroup(groupID:group.id);try valid(stamp)
        execution = .init();state = .init(groupID:group.id);pendingInput = nil;draft = "";nextBeforeID = nil
        executionSyncPending = false;errorMessage = nil
    }
    public func delete() async throws {
        leave();let stamp = epoch
        _ = try await api.deleteGroup(id:group.id);try valid(stamp)
        try await repository?.removeGroup(groupID:group.id)
    }
    private func friendly(_ error: Error) -> String {
        if let error = error as? APIError {
            if error.status == 429 {return "今日额度已用完，请稍后继续。"}
            if error.status == 426 {return "群聊需要更新后端服务后才能继续。"}
            if error.status == 409 {return "群聊状态已更新，请同步最新进度后继续。"}
        }
        return pendingInput == nil ? "伙伴们暂时没连上，请重新加载后再试。" : "发送结果暂未确认，请恢复连接后确认发送状态。"
    }
    private func observeExecution(stamp: Int) {
        observerTask?.cancel()
        observerTask = Task {
            var failures = 0
            while true {
                do {
                    try valid(stamp)
                    for try await event in api.observeGroupExecution(groupID:group.id,afterID:execution.snapshot.eventCursor) {
                        try valid(stamp)
                        guard GroupExecutionReducer.apply(event,to:&execution,groupID:group.id) else {continue}
                        if event.kind == "group_cleared" {
                            task?.cancel();task = nil;sending = false;pendingInput = nil;draft = ""
                            displayExecution()
                            try await repository?.clearGroup(groupID:group.id)
                            try valid(stamp)
                        }
                        executionSyncPending = false;displayExecution();try await persistExecution(stamp)
                    }
                    try valid(stamp)
                    let latest = try await api.groupExecution(groupID:group.id)
                    try valid(stamp)
                    // Old servers omit atomic messages; fetch history and replay from the previous cursor.
                    if latest.messages == nil {
                        let page = try await api.groupMessages(groupID:group.id,beforeID:nil)
                        try valid(stamp)
                        for message in page.messages {
                            if let index = state.messages.firstIndex(where:{$0.id == message.id}) {state.messages[index] = message}
                            else {state.messages.append(message)}
                        }
                    }
                    acceptSnapshot(latest);try await persistExecution(stamp)
                    if latest.task?.state == .running || latest.task?.state == .queued {try await Task.sleep(for:.milliseconds(250));continue}
                    return
                } catch is CancellationError {return}
                catch {
                    guard stamp == epoch,sessionIsCurrent() else {return}
                    executionSyncPending = true;failures += 1
                    if failures >= 3 {errorMessage = friendly(error);return}
                    do {try await Task.sleep(for:.milliseconds(250*failures));try valid(stamp)} catch {return}
                }
            }
        }
    }
}
