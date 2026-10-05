// MCP M3：待确认操作 / 工具调用记录。
import Foundation
import VeraBotCore

extension APIClient {
    public func pendingActions(status: String?, botID: Int?) async throws -> PendingActionsResponse {
        var q: [URLQueryItem] = []
        if let status { q.append(URLQueryItem(name: "status", value: status)) }
        if let botID { q.append(URLQueryItem(name: "bot_id", value: String(botID))) }
        return try await call("/api/pending-actions", query: q)
    }

    public func pendingAction(id: Int) async throws -> PendingAction {
        try await call("/api/pending-actions/\(id)")
    }

    public func confirmPendingAction(id: Int) async throws -> PendingAction {
        try await call("/api/pending-actions/\(id)/confirm", method: "POST")
    }

    public func cancelPendingAction(id: Int) async throws -> PendingAction {
        try await call("/api/pending-actions/\(id)/cancel", method: "POST")
    }

    public func toolCalls(botID: Int) async throws -> ToolCallsResponse {
        try await call("/api/bots/\(botID)/tool-calls")
    }
}
