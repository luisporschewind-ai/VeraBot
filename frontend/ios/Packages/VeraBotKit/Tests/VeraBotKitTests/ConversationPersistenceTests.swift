import Foundation
import Testing
import VeraBotCore
import VeraBotPersistence

@Test func deletingSyncedPrivateMessageRemovesItFromOfflineHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = LocalDatabase(url: directory.appendingPathComponent("conversation.sqlite"))
    defer { database.close() }
    let store = ConversationStore(database: database)
    let remote = try JSONDecoder().decode(ChatMessage.self, from: Data(#"{"id":17,"role":"user","content":"delete me","created_at":"now","traces":[]}"#.utf8))
    let message = LocalPrivateMessage(remote)
    try await store.stagePage([(id:17,value:message)],kind:"private",conversationID:3,revision:1,nextBeforeID:nil)
    let committed = try await store.finishSnapshot([message],remoteIDs:[17],kind:"private",conversationID:3,revision:1,sortKey:{$0.remoteID ?? 0},id:{$0.remoteID ?? 0})
    #expect(committed)
    try await store.deleteMessage(localID:message.id.uuidString,kind:"private",conversationID:3,remoteID:message.remoteID)
    let restored = try await store.messages(LocalPrivateMessage.self,kind:"private",conversationID:3)
    #expect(restored.isEmpty)
}
