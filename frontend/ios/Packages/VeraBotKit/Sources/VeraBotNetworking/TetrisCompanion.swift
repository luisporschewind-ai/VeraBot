import Foundation

public struct TetrisCompanionTurn: Codable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public let role: String
    public let content: String
    enum CodingKeys: String, CodingKey { case role, content }
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct TetrisCompanionRequest: Encodable, Sendable {
    public let event: String
    public let score: Int
    public let lines: Int
    public let height: Int
    public let holes: Int
    public var cleared: Int = 0
    public var message = ""
    public var history: [TetrisCompanionTurn] = []
    public init(event: String, score: Int, lines: Int, height: Int, holes: Int) {
        self.event = event; self.score = score; self.lines = lines; self.height = height; self.holes = holes
    }
}
public struct TetrisCompanionReply: Decodable, Sendable { public let text: String }

extension APIClient {
    public func tetrisCompanion(botID: Int, request: TetrisCompanionRequest) async throws -> TetrisCompanionReply {
        try await call("/api/bots/\(botID)/tetris-companion", method: "POST", body: JSONEncoder().encode(request))
    }
}
extension VeraBotAPI {
    public func tetrisCompanion(botID: Int, request: TetrisCompanionRequest) async throws -> TetrisCompanionReply {
        throw APIError(status: 501, message: "当前服务暂不支持陪玩回应")
    }
}
