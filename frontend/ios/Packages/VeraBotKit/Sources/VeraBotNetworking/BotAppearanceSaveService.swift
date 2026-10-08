import Foundation
import VeraBotCore

public enum BotAppearanceSaveError: Error, LocalizedError, Sendable {
    case unverifiedResponse
    public var errorDescription: String? { "服务端未确认保存此外观。请检查服务端版本后重试，当前草稿已保留。" }
}

public struct BotAppearanceSaveService: Sendable {
    private let api: any VeraBotAPI
    public init(api: any VeraBotAPI) { self.api = api }
    public func save(botID: Int, appearance: BotAppearance?) async throws -> Bot {
        let payload = try appearance?.jsonValue() ?? .null
        let bot = try await api.updateBot(botID, BotPatch(appearance: payload))
        guard bot.id == botID, bot.appearanceFieldPresent,
              appearance == nil ? bot.appearance == nil : bot.supportedAppearance == appearance else {
            throw BotAppearanceSaveError.unverifiedResponse
        }
        return bot
    }
}
