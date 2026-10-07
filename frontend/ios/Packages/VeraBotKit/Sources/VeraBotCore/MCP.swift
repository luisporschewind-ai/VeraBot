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
    public let grantedScopes: String?
    public let toolsCount: Int
    public let lastError: String?
    public let lastSyncedAt: String?
    /// 同意把该服务的工具结果发给 DeepSeek 的时间。空表示还没同意或已撤回。
    public let consentAt: String?
    /// pending / syncing / ok / error。旧响应没有这个字段时当作 pending。
    public let syncStatus: String?
    /// closed / open / half_open。
    public let circuitState: String?
    public let circuitOpenUntil: String?
    public let consecutiveFailures: Int?
    public let requiredScopes: [String]?

    public var consented: Bool { !(consentAt ?? "").isEmpty }

    public var statusText: String {
        if !enabled || status == "disabled" { return "已停用" }
        if circuitState == "open" { return "已熔断" }
        switch syncStatus {
        case "syncing": return "正在同步"
        case "pending": return "等待同步"
        case "error": return "同步失败"
        case "ok" where !consented: return "未同意"
        default: break
        }
        switch status {
        case "connected": return "已连接"
        case "error": return "异常"
        case "expired": return "需要重新连接"
        case "needs_scope": return "需要追加权限"
        case "needs_auth": return "未连接"
        default: return status
        }
    }

    public var syncStatusText: String {
        switch syncStatus ?? "pending" {
        case "pending": return "等待同步"
        case "syncing": return "正在同步"
        case "ok": return "已同步"
        case "error": return "同步失败"
        default: return syncStatus ?? "等待同步"
        }
    }

    public var circuitText: String {
        switch circuitState ?? "closed" {
        case "open": return "已熔断"
        case "half_open": return "恢复探测"
        default: return "正常"
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
        case grantedScopes = "granted_scopes"
        case toolsCount = "tools_count"
        case lastError = "last_error"
        case lastSyncedAt = "last_synced_at"
        case consentAt = "consent_at"
        case syncStatus = "sync_status"
        case circuitState = "circuit_state"
        case circuitOpenUntil = "circuit_open_until"
        case consecutiveFailures = "consecutive_failures"
        case requiredScopes = "required_scopes"
    }
}

public struct MCPServersResponse: Codable, Sendable {
    public let servers: [MCPServer]
}

public struct MCPOAuthStart: Codable, Sendable {
    public let authURL: URL
    public let state: String
    public let callbackScheme: String
    enum CodingKeys: String, CodingKey {
        case authURL = "auth_url"
        case state
        case callbackScheme = "callback_scheme"
    }
}

public struct MCPOAuthCallback: Codable, Sendable {
    public let code: String
    public let state: String
    public let issuer: String?
    public init(code: String, state: String, issuer: String? = nil) {
        self.code = code
        self.state = state
        self.issuer = issuer
    }
    enum CodingKeys: String, CodingKey {
        case code, state
        case issuer = "iss"
    }
}

public struct MCPOAuthResult: Codable, Sendable {
    public let status: String
    public let toolsCount: Int
    public let syncStatus: String?
    enum CodingKeys: String, CodingKey {
        case status
        case toolsCount = "tools_count"
        case syncStatus = "sync_status"
    }
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
    /// 所属插件。旧响应没有这个字段时为 nil。
    public let pluginId: String?

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
        case pluginId = "plugin_id"
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

/// 对话里 MCP 工具调用的显示文字。trace 只有完整函数名 `mcp__{slug}__{tool}` 与结果，
/// 不把外部原文直接铺在对话里（原文最长 8000 字，且是不可信数据）。
public enum MCPTraceText {
    static let serverNames = ["learn": "Microsoft Learn", "aws": "AWS Knowledge", "github": "GitHub", "linear": "Linear"]
    static let toolLabels = [
        "microsoft_docs_search": "搜索微软文档",
        "microsoft_code_sample_search": "搜索代码示例",
        "microsoft_docs_fetch": "获取微软文档",
        "aws___list_regions": "列出 AWS 区域",
        "get_file_contents": "读取文件",
        "list_branches": "列出分支",
        "list_commits": "列出提交",
        "get_commit": "查看提交",
        "list_tags": "列出标签",
        "list_releases": "列出发布",
        "get_latest_release": "查看最新发布",
        "search_code": "搜索代码",
        "search_repositories": "搜索仓库",
        "issue_read": "读取 issue",
        "list_issues": "列出 issue",
        "search_issues": "搜索 issue",
        "pull_request_read": "读取 PR",
        "list_pull_requests": "列出 PR",
        "search_pull_requests": "搜索 PR",
    ]

    public static func isMCP(_ name: String) -> Bool { name.hasPrefix("mcp__") }

    /// 工具原名（如 list_issues）的中文名；没有就用原名。
    public static func toolLabel(_ mcpName: String) -> String { toolLabels[mcpName] ?? mcpName }

    /// "mcp__learn__microsoft_docs_search" → "🔌 Microsoft Learn · 搜索微软文档"；非 MCP 名返回 nil。
    public static func title(for name: String) -> String? {
        guard isMCP(name) else { return nil }
        let rest = name.dropFirst("mcp__".count)
        guard let sep = rest.range(of: "__") else { return "🔌 \(rest)" }
        let slug = String(rest[..<sep.lowerBound])
        let tool = String(rest[sep.upperBound...])
        let server = serverNames[slug] ?? slug
        return "🔌 \(server) · \(toolLabels[tool] ?? tool)"
    }

    /// 成功结果的一行说明，不显示外部原文。
    public static func summary(contentLength: Int, truncated: Bool) -> String {
        "已读取外部资料（约 \(contentLength) 字\(truncated ? "，已截断" : "")），内容只作为参考信息"
    }

    /// 错误的一行说明。`mcp_tool_error` 的 error 字段是外部原文，不直接显示。
    public static func errorText(code: String?, error: String?) -> String? {
        switch code {
        case "mcp_tool_error": return "外部服务返回了错误"
        case "mcp_timeout": return "外部服务超时"
        case "mcp_rpc_error", "mcp_unavailable", "mcp_protocol", "mcp_session_expired": return "外部服务暂时不可用"
        case "mcp_consent_required": return "尚未同意把工具结果发送给 DeepSeek"
        case "mcp_circuit_open": return "该服务连续失败，已暂时停止连接"
        case "result_unknown": return "请求结果未知，请到对应服务核实"
        case "plugin_uninstalled": return "插件已卸载，本次调用已取消"
        case "mcp_auth_required": return "需要在插件页重新连接"
        case "mcp_permission_denied": return "服务拒绝：令牌没有这个资源或这项权限"
        default: return error
        }
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
