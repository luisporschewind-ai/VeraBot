import Foundation
import VeraBotCore

/// VeraBot 后端 API 抽象（Service protocol）。App 只依赖此协议，便于替换实现（Mock / 预览 / 其他传输层）。
public protocol VeraBotAPI: Sendable {
    func login(_ c: Credentials) async throws -> AuthResponse
    func register(_ c: Credentials) async throws -> AuthResponse
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
    func chatStream(botID: Int, message: String) -> AsyncThrowingStream<ChatEvent, Error>
}
