import Foundation
import VeraBotCore
import VeraBotNetworking
import VeraBotPersistence

public enum ConversationKind: String, Sendable { case privateChat = "private", group }

/// Coordinates account-scoped SQLite and the existing network APIs. It never treats a failed request as an empty snapshot.
public actor ConversationRepository {
    public let store: ConversationStore
    private let api: any VeraBotAPI
    private let groupAPI: any GroupChatAPI
    private let sessionIsCurrent: @Sendable () -> Bool
    private var invalidated = false
    private var mutationEpochs: [String: Int] = [:]
    private var syncTasks: [String: Task<Void, Error>] = [:]

    public init(store: ConversationStore, api: any VeraBotAPI, groupAPI: any GroupChatAPI,
                sessionIsCurrent: @escaping @Sendable () -> Bool) {
        self.store = store; self.api = api; self.groupAPI = groupAPI; self.sessionIsCurrent = sessionIsCurrent
    }

    public func cacheLists() async throws -> (bots: [Bot], groups: [ChatGroup]) {
        async let bots = store.conversations(Bot.self, kind: "bot")
        async let groups = store.conversations(ChatGroup.self, kind: ConversationKind.group.rawValue)
        return try await (bots, groups)
    }

    public func invalidate() {
        invalidated = true
        for task in syncTasks.values { task.cancel() }
    }

    public func replaceBots(_ bots: [Bot]) async throws {
        guard isCurrent else { throw CancellationError() }
        try await store.replaceConversations(bots, kind: "bot", id: \.id)
    }
    public func replaceGroups(_ groups: [ChatGroup]) async throws {
        guard isCurrent else { throw CancellationError() }
        try await store.replaceConversations(groups, kind: ConversationKind.group.rawValue, id: \.id)
    }

    public func refreshLists() async throws -> (bots: [Bot], groups: [ChatGroup]) {
        async let remoteBots = api.bots()
        async let remoteGroups = groupAPI.groups()
        let (bots, groups) = try await (remoteBots, remoteGroups)
        guard isCurrent else { throw CancellationError() }
        for bot in bots.bots {
            guard isCurrent else { throw CancellationError() }
            try await store.saveConversation(bot, kind: "bot", id: bot.id)
        }
        for group in groups.groups {
            guard isCurrent else { throw CancellationError() }
            try await store.saveConversation(group, kind: ConversationKind.group.rawValue, id: group.id)
        }
        return (bots.bots, groups.groups)
    }

    public func privateMessages(botID: Int, before: Int? = nil, limit: Int = 100) async throws -> [StoredMessage<LocalPrivateMessage>] {
        try await store.messages(LocalPrivateMessage.self, kind: ConversationKind.privateChat.rawValue,
                                 conversationID: botID, before: before, limit: limit)
    }

    public func savePrivate(_ message: LocalPrivateMessage, botID: Int, sortKey: Int, status: String) async throws {
        guard isCurrent else { throw CancellationError() }
        _ = try await store.saveMessage(message, kind: ConversationKind.privateChat.rawValue,
                                        conversationID: botID, localID: message.id.uuidString,
                                        remoteID: message.remoteID, sortKey: sortKey, status: status)
    }
    public func deletePrivate(_ message: LocalPrivateMessage, botID: Int) async throws {
        guard isCurrent else { throw CancellationError() }
        invalidateSync(kind: .privateChat, id: botID)
        try await store.deleteMessage(localID: message.id.uuidString, kind: ConversationKind.privateChat.rawValue,
                                      conversationID: botID, remoteID: message.remoteID)
    }
    public func clearPrivate(botID: Int) async throws {
        guard isCurrent else { throw CancellationError() }
        invalidateSync(kind: .privateChat, id: botID)
        try await store.clearMessages(kind: ConversationKind.privateChat.rawValue, id: botID)
    }
    public func saveDraft(_ text: String, kind: ConversationKind, id: Int) async throws {
        guard isCurrent else { throw CancellationError() }
        try await store.saveDraft(text, kind: kind.rawValue, conversationID: id)
    }
    public func draft(kind: ConversationKind, id: Int) async throws -> String {
        try await store.draft(kind: kind.rawValue, conversationID: id)
    }
    public func isHistoryComplete(kind: ConversationKind, id: Int) async throws -> Bool {
        try await store.isComplete(kind: kind.rawValue, conversationID: id)
    }

    public func groupMessages(groupID: Int, before: Int? = nil, limit: Int = 100) async throws -> [StoredMessage<GroupMessage>] {
        try await store.messages(GroupMessage.self, kind: ConversationKind.group.rawValue,
                                 conversationID: groupID, before: before, limit: limit)
    }
    public func cachedGroup(id: Int) async throws -> ChatGroup? {
        try await store.conversations(ChatGroup.self, kind: ConversationKind.group.rawValue).first { $0.id == id }
    }
    public func saveGroupMessage(_ message: GroupMessage, groupID: Int, status: String) async throws {
        guard isCurrent else { throw CancellationError() }
        _ = try await store.saveMessage(message, kind: ConversationKind.group.rawValue, conversationID: groupID,
                                        localID: "group-\(groupID)-\(message.id)", remoteID: message.id,
                                        sortKey: message.id, status: status)
    }
    public func pendingGroupInput(groupID: Int) async throws -> GroupInputRequest? {
        guard isCurrent else {throw CancellationError()}
        return try await store.pendingGroupInput(GroupInputRequest.self,conversationID:groupID)
    }
    public func savePendingGroupInput(_ input: GroupInputRequest?, groupID: Int) async throws {
        guard isCurrent else {throw CancellationError()}
        try await store.savePendingGroupInput(input,conversationID:groupID)
    }
    public func groupExecutionSnapshot(groupID: Int) async throws -> GroupExecutionSnapshot? {
        guard isCurrent else { throw CancellationError() }
        return try await store.groupExecutionSnapshot(GroupExecutionSnapshot.self, conversationID: groupID)
    }
    public func saveGroupExecution(_ snapshot: GroupExecutionSnapshot, messages: [GroupMessage], groupID: Int) async throws {
        guard isCurrent else { throw CancellationError() }
        try await store.saveGroupExecution(snapshot, messages: messages, id: \.id,
                                           status: { $0.status.rawValue }, conversationID: groupID)
    }
    public func clearGroup(groupID: Int) async throws {
        guard isCurrent else { throw CancellationError() }
        invalidateSync(kind: .group, id: groupID)
        try await store.clearMessages(kind: ConversationKind.group.rawValue, id: groupID)
    }
    public func markGroupHistoryComplete(groupID: Int, revision: Int64) async throws {
        guard isCurrent else { throw CancellationError() }
        try await store.markComplete(kind: ConversationKind.group.rawValue, conversationID: groupID, revision: revision)
    }
    public func removeGroup(groupID: Int) async throws {
        guard isCurrent else { throw CancellationError() }
        invalidateSync(kind: .group, id: groupID)
        try await store.deleteConversation(kind: ConversationKind.group.rawValue, id: groupID)
    }

    public func syncPrivate(botID: Int) async throws {
        try await sync(kind: .privateChat, conversationID: botID, fetch: { [api, store] (cursor: Int?, revision: Int64?) -> Page<LocalPrivateMessage> in
            let response = try await api.syncMessages(botID: botID, beforeID: cursor, expectedRevision: revision)
            let existing = try await store.messages(LocalPrivateMessage.self, kind: "private", conversationID: botID, limit: 100_000)
            let identities = Dictionary(uniqueKeysWithValues: existing.compactMap { row -> (Int, UUID)? in guard let id = row.remoteID else { return nil }; return (id, row.value.id) })
            return Page<LocalPrivateMessage>(revision: response.revision, messages: response.messages.map { LocalPrivateMessage($0, id: identities[$0.id] ?? UUID()) },
                        nextBeforeID: response.nextBeforeID, unchanged: response.unchanged)
        }, id: { (message: LocalPrivateMessage) in message.remoteID ?? 0 },
           sort: { (message: LocalPrivateMessage) in message.remoteID ?? 0 })
    }

    public func syncGroup(groupID: Int) async throws {
        try await sync(kind: .group, conversationID: groupID, fetch: { [groupAPI] cursor, revision in
            let response = try await groupAPI.syncGroupMessages(groupID: groupID, beforeID: cursor, expectedRevision: revision)
            return Page(revision: response.revision, messages: response.messages,
                        nextBeforeID: response.nextBeforeID, unchanged: response.unchanged)
        }, id: { $0.id }, sort: { $0.id })
    }

    private func sync<Value: Codable & Sendable>(kind: ConversationKind, conversationID: Int,
                                                 fetch: @escaping @Sendable (Int?, Int64?) async throws -> Page<Value>,
                                                 id: @escaping @Sendable (Value) -> Int,
                                                 sort: @escaping @Sendable (Value) -> Int) async throws {
        try Task.checkCancellation()
        guard isCurrent else { throw CancellationError() }
        let key = "\(kind.rawValue):\(conversationID)"
        if let task = syncTasks[key] {
            try await task.value
        } else {
            // Actor methods can interleave at every await. Keep one owner of a
            // conversation's staging rows until the entire snapshot finishes.
            let task = Task {
                // Clear the entry before resuming any caller, including on failure.
                defer { syncTasks.removeValue(forKey: key) }
                do {
                    try await performSync(kind: kind, conversationID: conversationID, fetch: fetch, id: id, sort: sort)
                } catch {
                    if !isCurrent || Task.isCancelled { throw CancellationError() }
                    throw error
                }
            }
            syncTasks[key] = task
            try await task.value
        }
        try Task.checkCancellation()
        guard isCurrent else { throw CancellationError() }
    }

    private func performSync<Value: Codable & Sendable>(kind: ConversationKind, conversationID: Int,
                                                        fetch: @Sendable (Int?, Int64?) async throws -> Page<Value>,
                                                        id: @Sendable (Value) -> Int,
                                                        sort: @Sendable (Value) -> Int) async throws {
        for _ in 0..<3 {
            guard isCurrent else { throw CancellationError() }
            let runEpoch = mutationEpoch(kind: kind, id: conversationID)
            let saved = try await store.syncState(kind: kind.rawValue, conversationID: conversationID)
            var revision = saved.activeRevision ?? saved.revision
            var cursor = saved.activeRevision == nil ? nil : saved.beforeID
            var restart = false
            do {
                while true {
                    try Task.checkCancellation()
                    guard isCurrent else { throw CancellationError() }
                    let page = try await fetch(cursor, revision)
                    try Task.checkCancellation()
                    guard isCurrent else { throw CancellationError() }
                    guard mutationEpoch(kind: kind, id: conversationID) == runEpoch else { restart = true; break }
                    if page.unchanged && cursor == nil {
                        // A completed snapshot can use the fast path. If an earlier run
                        // staged its final page but died before finishSnapshot, restart
                        // the snapshot so stale staging can never masquerade as complete.
                        if saved.activeRevision == nil { return }
                        restart = true
                        break
                    }
                    if revision == nil { revision = page.revision }
                    guard let pinned = revision, pinned == page.revision else { restart = true; break }
                    try await store.stagePage(page.messages.map { (id: id($0), value: $0) },
                                              kind: kind.rawValue, conversationID: conversationID,
                                              revision: pinned, nextBeforeID: page.nextBeforeID)
                    try Task.checkCancellation()
                    guard isCurrent else { throw CancellationError() }
                    guard mutationEpoch(kind: kind, id: conversationID) == runEpoch else { restart = true; break }
                    cursor = page.nextBeforeID
                    if cursor == nil {
                        let all = try await store.stagedMessages(Value.self, kind: kind.rawValue,
                                                                 conversationID: conversationID, revision: pinned)
                        try Task.checkCancellation()
                        guard isCurrent else { throw CancellationError() }
                        guard mutationEpoch(kind: kind, id: conversationID) == runEpoch else { restart = true; break }
                        let values = all.map(\.value)
                        let committed = try await store.finishSnapshot(values, remoteIDs: all.map(\.id), kind: kind.rawValue,
                                                                       conversationID: conversationID, revision: pinned,
                                                                       sortKey: sort, id: id)
                        if committed { return }
                        restart = true
                        break
                    }
                }
            } catch let error as APIError where error.status == 409 && error.code == "sync_revision_changed" {
                restart = true
            }
            if restart {
                try Task.checkCancellation()
                guard isCurrent else { throw CancellationError() }
                try await store.restartSync(kind: kind.rawValue, conversationID: conversationID)
                continue
            }
            return
        }
        throw APIError(status: 409, message: "对话仍在更新，稍后会继续同步。", code: "sync_revision_changed")
    }
}

private extension ConversationRepository {
    var isCurrent: Bool { !invalidated && sessionIsCurrent() }
    func mutationEpoch(kind: ConversationKind, id: Int) -> Int {
        mutationEpochs["\(kind.rawValue):\(id)", default: 0]
    }
    func invalidateSync(kind: ConversationKind, id: Int) {
        mutationEpochs["\(kind.rawValue):\(id)", default: 0] += 1
    }
}

public struct Page<Value: Codable & Sendable>: Sendable {
    public let revision: Int64
    public let messages: [Value]
    public let nextBeforeID: Int?
    public let unchanged: Bool
    public init(revision: Int64, messages: [Value], nextBeforeID: Int?, unchanged: Bool) {
        self.revision = revision; self.messages = messages; self.nextBeforeID = nextBeforeID; self.unchanged = unchanged
    }
    public init(_ page: MessageSyncResponse) where Value == ChatMessage {
        revision = page.revision; messages = page.messages; nextBeforeID = page.nextBeforeID; unchanged = page.unchanged
    }
    public init(_ page: GroupMessagesSyncResponse) where Value == GroupMessage {
        revision = page.revision; messages = page.messages; nextBeforeID = page.nextBeforeID; unchanged = page.unchanged
    }
}

