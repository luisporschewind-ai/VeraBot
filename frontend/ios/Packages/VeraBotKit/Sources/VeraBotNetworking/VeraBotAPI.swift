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
    func delegations(botID: Int) async throws -> DelegationsResponse
    func messages(botID: Int) async throws -> MessagesResponse
    func clearMessages(botID: Int) async throws -> OKResponse
    func reminders() async throws -> RemindersResponse
    func completeReminder(_ id: Int) async throws -> OKResponse
    func quota() async throws -> Quota
    func health() async throws -> HealthStatus
    func chatStream(botID: Int, message: String) -> AsyncThrowingStream<ChatEvent, Error>
}
