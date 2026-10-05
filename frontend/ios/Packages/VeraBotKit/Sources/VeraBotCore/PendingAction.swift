// PendingAction：MCP M3 待确认操作（与后端 /api/pending-actions、SSE confirmation_required 对照）。
import Foundation

public enum ToolRisk: String, Codable, Sendable, Hashable {
    case read, write, send, destructive
    case unknown

    public init(raw: String?) {
        self = ToolRisk(rawValue: raw ?? "") ?? .unknown
    }

    public var label: String {
        switch self {
        case .read: return "只读"
        case .write: return "写入"
        case .send: return "发送"
        case .destructive: return "破坏性"
        case .unknown: return "需确认"
        }
    }
}

/// 待确认操作。`id` 即 `action_id`。
public struct PendingAction: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let kind: String
    public let status: String
    public let botId: Int?
    public let serverId: Int?
    public let server: String?
    public let tool: String?
    public let label: String?
    public let risk: String?
    public let arguments: JSONValue?
    public let warnings: [String]
    public let result: String?
    public let createdAt: String?
    public let expiresAt: String?
    public let decidedAt: String?
    public let argsUnavailable: Bool?

    public var toolRisk: ToolRisk { ToolRisk(raw: risk) }
    public var isPending: Bool { status == "pending" }

    public init(
        id: Int, kind: String = "mcp_tool_call", status: String = "pending",
        botId: Int? = nil, serverId: Int? = nil, server: String? = nil,
        tool: String? = nil, label: String? = nil, risk: String? = nil,
        arguments: JSONValue? = nil, warnings: [String] = [], result: String? = nil,
        createdAt: String? = nil, expiresAt: String? = nil, decidedAt: String? = nil,
        argsUnavailable: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.botId = botId
        self.serverId = serverId
        self.server = server
        self.tool = tool
        self.label = label
        self.risk = risk
        self.arguments = arguments
        self.warnings = warnings
        self.result = result
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.decidedAt = decidedAt
        self.argsUnavailable = argsUnavailable
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, status, server, tool, label, risk, arguments, warnings, result
        case botId = "bot_id"
        case serverId = "server_id"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case decidedAt = "decided_at"
        case argsUnavailable = "args_unavailable"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "mcp_tool_call"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        botId = try c.decodeIfPresent(Int.self, forKey: .botId)
        serverId = try c.decodeIfPresent(Int.self, forKey: .serverId)
        server = try c.decodeIfPresent(String.self, forKey: .server)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        risk = try c.decodeIfPresent(String.self, forKey: .risk)
        arguments = try c.decodeIfPresent(JSONValue.self, forKey: .arguments)
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        result = try c.decodeIfPresent(String.self, forKey: .result)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        decidedAt = try c.decodeIfPresent(String.self, forKey: .decidedAt)
        argsUnavailable = try c.decodeIfPresent(Bool.self, forKey: .argsUnavailable)
    }
}

public struct PendingActionsResponse: Codable, Sendable {
    public let actions: [PendingAction]
}

/// SSE `confirmation_required`（字段与设计 §12.1 一致；另含 server_id）。
public struct ConfirmationRequired: Codable, Sendable, Hashable, Identifiable {
    public let actionId: Int
    public let kind: String
    public let server: String?
    public let serverId: Int?
    public let tool: String?
    public let label: String?
    public let arguments: JSONValue?
    public let risk: String?
    public let warnings: [String]
    public let expiresAt: String?

    public var id: Int { actionId }
    public var toolRisk: ToolRisk { ToolRisk(raw: risk) }

    enum CodingKeys: String, CodingKey {
        case kind, server, tool, label, arguments, risk, warnings
        case actionId = "action_id"
        case serverId = "server_id"
        case expiresAt = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        actionId = try c.decode(Int.self, forKey: .actionId)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "mcp_tool_call"
        server = try c.decodeIfPresent(String.self, forKey: .server)
        serverId = try c.decodeIfPresent(Int.self, forKey: .serverId)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        arguments = try c.decodeIfPresent(JSONValue.self, forKey: .arguments)
        risk = try c.decodeIfPresent(String.self, forKey: .risk)
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
    }

    /// 从 tool_result（pending_confirmation）构造，便于历史重载。
    public init?(toolResult: JSONValue) {
        guard toolResult["status"]?.text == "pending_confirmation",
              case .number(let n)? = toolResult["action_id"] else { return nil }
        actionId = Int(n)
        kind = toolResult["kind"]?.text ?? "mcp_tool_call"
        server = toolResult["server"]?.text
        if case .number(let sid)? = toolResult["server_id"] { serverId = Int(sid) } else { serverId = nil }
        tool = toolResult["tool"]?.text
        label = toolResult["label"]?.text
        arguments = toolResult["arguments"]
        risk = toolResult["risk"]?.text
        if case .array(let arr)? = toolResult["warnings"] {
            warnings = arr.compactMap(\.text)
        } else {
            warnings = []
        }
        expiresAt = toolResult["expires_at"]?.text
    }

    public func asPending(status: String = "pending") -> PendingAction {
        PendingAction(
            id: actionId, kind: kind, status: status, botId: nil, serverId: serverId,
            server: server, tool: tool, label: label, risk: risk, arguments: arguments,
            warnings: warnings, expiresAt: expiresAt
        )
    }
}

public struct ToolCallRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let kind: String
    public let createdAt: String?
    public let server: JSONValue?
    public let tool: String?
    public let status: String?
    public let actionId: Int?
    public let durationMs: Double?

    enum CodingKeys: String, CodingKey {
        case id, kind, server, tool, status
        case createdAt = "created_at"
        case actionId = "action_id"
        case durationMs = "duration_ms"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        server = try c.decodeIfPresent(JSONValue.self, forKey: .server)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        if let n = try c.decodeIfPresent(Int.self, forKey: .actionId) {
            actionId = n
        } else if let d = try c.decodeIfPresent(Double.self, forKey: .actionId) {
            actionId = Int(d)
        } else {
            actionId = nil
        }
        durationMs = try c.decodeIfPresent(Double.self, forKey: .durationMs)
    }
}

public struct ToolCallsResponse: Codable, Sendable {
    public let toolCalls: [ToolCallRecord]
    enum CodingKeys: String, CodingKey { case toolCalls = "tool_calls" }
}

extension ToolTrace {
    /// 工具结果为 pending_confirmation 时解析出确认卡片数据。
    public var pendingConfirmation: ConfirmationRequired? {
        guard let r = result else { return nil }
        return ConfirmationRequired(toolResult: r)
    }
}

extension JSONValue {
    /// 确认卡片参数表：扁平键值（一层）。
    public var argumentPairs: [(String, String)] {
        guard case .object(let obj) = self else { return [] }
        return obj.keys.sorted().map { key in
            (key, (obj[key] ?? .null).displayText)
        }
    }

    public var displayText: String {
        switch self {
        case .string(let s): return s
        case .number(let n):
            if n == Double(Int(n)) { return String(Int(n)) }
            return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array, .object:
            if let data = try? JSONEncoder().encode(self),
               let s = String(data: data, encoding: .utf8) { return s }
            return "…"
        }
    }
}
