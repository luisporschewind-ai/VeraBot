import Foundation
import VeraBotCore

/// VeraBot 后端 API 抽象（Service protocol）。App 只依赖此协议，便于替换实现（Mock / 预览 / 其他传输层）。
public protocol VeraBotAPI: Sendable {
    func login(_ c: Credentials) async throws -> AuthResponse
    func register(_ c: Credentials) async throws -> AuthResponse
    func me() async throws -> User
    func updateNickname(_ nickname: String) async throws -> User
    func uploadMyAvatar(jpeg: Data) async throws -> User
    func myAvatarData() async throws -> Data
    func deleteMyAvatar() async throws -> User
    func uploadBotAvatar(botID: Int, jpeg: Data) async throws -> Bot
    func botAvatarData(botID: Int) async throws -> Data
    func deleteBotAvatar(botID: Int) async throws -> Bot
    func bots() async throws -> BotsResponse
    func createBot(_ b: BotCreate) async throws -> Bot
    func deleteBot(_ id: Int) async throws -> OKResponse
    func updateBot(_ id: Int, _ patch: BotPatch) async throws -> Bot
    func tools() async throws -> ToolsResponse
    func mcpCatalog() async throws -> MCPCatalogResponse
    func mcpServers() async throws -> MCPServersResponse
    func addMCPServer(catalogID: String) async throws -> MCPServer
    func updateMCPServer(id: Int, enabled: Bool) async throws -> MCPServer
    func deleteMCPServer(id: Int) async throws -> OKResponse
    func syncMCPServer(id: Int) async throws -> MCPSyncResult
    func mcpTools(serverID: Int) async throws -> MCPToolsResponse
    func delegations(botID: Int) async throws -> DelegationsResponse
    func messages(botID: Int) async throws -> MessagesResponse
    /// includeMemories：同时删除该 Bot 的「本 Bot 记忆」与对话摘要（默认 false，记忆保留）
    func clearMessages(botID: Int, includeMemories: Bool) async throws -> ClearMessagesResponse
    // 长期记忆（Memory，后端 schema v4）
    func memories(_ query: MemoryQuery) async throws -> MemoriesResponse
    func memory(id: Int) async throws -> Memory
    func createMemory(_ m: MemoryCreate) async throws -> Memory
    func updateMemory(id: Int, _ patch: MemoryPatch) async throws -> Memory
    func deleteMemory(id: Int) async throws -> OKResponse
    /// scope nil = 全部；.bot 需传 botID
    func clearMemories(scope: MemoryScope?, botID: Int?) async throws -> MemoryClearResponse
    func confirmMemory(id: Int, content: String?) async throws -> MemoryConfirmResult
    func rejectMemory(id: Int) async throws -> OKResponse
    func memorySettings() async throws -> MemorySettings
    func updateMemorySettings(enabled: Bool) async throws -> MemorySettings
    func reminders() async throws -> RemindersResponse
    func completeReminder(_ id: Int) async throws -> OKResponse
    func quota() async throws -> Quota
    func health() async throws -> HealthStatus
    func chatStream(botID: Int, message: String) -> AsyncThrowingStream<ChatEvent, Error>
}
