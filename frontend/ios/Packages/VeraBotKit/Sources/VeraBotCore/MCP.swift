// MCP 服务与工具。字段名与后端 /api/mcp/*、/api/tools 一致。
import Foundation

public struct MCPCatalogItem: Codable, Sendable, Hashable, Identifiable {
    public let catalogId: String
    public let slug: String
    public let name: String
    public let description: String
    public let trust: String
    public let transport: String
    public let auth: String
    public let enabledByDefault: Bool
    public let urlConfigured: Bool
    public var id: String { catalogId }

    enum CodingKeys: String, CodingKey {
        case catalogId = "catalog_id"
        case slug
        case name
        case description
        case trust
        case transport
        case auth
        case enabledByDefault = "enabled_by_default"
        case urlConfigured = "url_configured"
    }
}

public struct MCPCatalogResponse: Codable, Sendable {
    public let catalog: [MCPCatalogItem]
}

public struct MCPServer: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let slug: String
    public let catalogId: String?
    public let name: String
    public let source: String
    public let transport: String
    public let trust: String
    public let authType: String
    public let status: String
    public let enabled: Bool
    public let accountLabel: String?
    public let toolsCount: Int
    public let lastError: String?
    public let lastSyncedAt: String?

    public var statusText: String {
        switch status {
        case "connected": return "已连接"
        case "disabled": return "已停用"
        case "error": return "异常"
        case "expired": return "需要重新连接"
        case "needs_scope": return "需要追加权限"
        case "needs_auth": return "未连接"
        default: return status
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case catalogId = "catalog_id"
        case name
        case source
        case transport
        case trust
        case authType = "auth_type"
        case status
        case enabled
        case accountLabel = "account_label"
        case toolsCount = "tools_count"
        case lastError = "last_error"
        case lastSyncedAt = "last_synced_at"
    }
}

public struct MCPServersResponse: Codable, Sendable {
    public let servers: [MCPServer]
}

public struct MCPTool: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let serverId: Int
    public let fullName: String
    public let mcpName: String
    public let label: String
    public let description: String
    public let risk: String
    public let requiresConfirmation: Bool
    public let delegable: Bool
    public let status: String

    public var riskText: String {
        switch risk {
        case "read": return "只读"
        case "write": return "写入"
        case "send": return "发送"
        case "destructive": return "破坏性"
        default: return risk
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case serverId = "server_id"
        case fullName = "full_name"
        case mcpName = "mcp_name"
        case label
        case description
        case risk
        case requiresConfirmation = "requires_confirmation"
        case delegable
        case status
    }
}

public struct MCPToolsResponse: Codable, Sendable {
    public let tools: [MCPTool]
}

public struct MCPSyncResult: Codable, Sendable {
    public let added: [String]
    public let changed: [String]
    public let removed: [String]
    public let server: MCPServer

    enum CodingKeys: String, CodingKey {
        case added
        case changed
        case removed
        case server
    }
}

/// 每个 Bot 最多 20 个 MCP 工具。「开启全部只读」展开成具体工具名，不隐式包含以后新增的工具。
public enum MCPToolRules {
    public static let maxPerBot = 20

    public static func addingReadOnly(current: [String], tools: [MCPTool]) -> [String] {
        var next = current
        for tool in tools where tool.risk == "read" && tool.status == "active" {
            if next.contains(tool.fullName) { continue }
            if next.filter({ $0.hasPrefix("mcp__") }).count >= maxPerBot { break }
            next.append(tool.fullName)
        }
        return next
    }
}
