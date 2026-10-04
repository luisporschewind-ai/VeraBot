// 插件。字段名与后端 /api/plugins/* 一致。MCP 仍是实现细节，不出现在这些类型的展示文案里。
import Foundation

public struct Plugin: Decodable, Sendable, Hashable, Identifiable {
    public let pluginId: String
    public let kind: String
    public let name: String
    public let description: String
    public let category: String
    public let publisher: String
    public let version: String
    public let icon: String
    public let authMode: String
    public let trust: String
    public let installed: Bool
    public let available: Bool
    public let removable: Bool
    public let enabled: Bool
    public let state: String
    public let consentRequired: Bool
    public let consentAt: String?
    public let dataNotice: String
    public let toolsCount: Int
    public let syncStatus: String?
    public let lastSyncedAt: String?
    public let lastError: String?
    public let circuitState: String?
    public let circuitOpenUntil: String?
    public let consecutiveFailures: Int
    public let servers: [MCPServer]
    // v13 需授权连接器（后端可选字段，旧后端缺键为 nil / 空）。令牌本身永远不在响应里。
    public let authConnected: Bool?
    public let accountLabel: String?
    public let credentialHint: String?
    public let credentialExpiresAt: String?
    public let authError: String?
    public let credentialHelp: String?
    public let credentialHelpURL: String?
    public let toolsChanged: [String]

    public var id: String { pluginId }
    /// 需要用户提供令牌（auth_mode = bearer）
    public var needsToken: Bool { authMode == "bearer" }

    /// 授权错误的一行说明（详情页「账号」分组）。
    public var authErrorText: String? {
        switch authError ?? "" {
        case "token_invalid": return "令牌无效或已撤销"
        case "expired": return "授权已过期"
        case "insufficient_scope": return "权限不足"
        case "network_unreachable": return "网络不可达"
        case "": return nil
        default: return authError
        }
    }
    public var isBuiltin: Bool { kind == "builtin" }
    public var consented: Bool { !(consentAt ?? "").isEmpty }

    /// 插件页副标题。内置插件固定一句；外部插件只映射后端算好的 state。
    public var stateTitle: String {
        if isBuiltin { return "内置 · 无需安装" }
        switch state {
        case "ready": return "可用"
        case "needs_auth": return "需要连接"
        case "needs_consent": return "待同意"
        case "syncing": return "正在同步"
        case "disabled": return "已停用"
        case "circuit_open": return "已熔断"
        case "error": return "同步失败"
        case "not_installed": return "未安装"
        default: return state
        }
    }

    public var syncStatusText: String {
        switch syncStatus ?? "" {
        case "pending": return "等待同步"
        case "syncing": return "正在同步"
        case "ok": return "已同步"
        case "error": return "同步失败"
        case "": return "无需同步"
        default: return syncStatus ?? "无需同步"
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
        case pluginId = "plugin_id"
        case kind
        case name
        case description
        case category
        case publisher
        case version
        case icon
        case authMode = "auth_mode"
        case trust
        case installed
        case available
        case removable
        case enabled
        case state
        case consentRequired = "consent_required"
        case consentAt = "consent_at"
        case dataNotice = "data_notice"
        case toolsCount = "tools_count"
        case syncStatus = "sync_status"
        case lastSyncedAt = "last_synced_at"
        case lastError = "last_error"
        case circuitState = "circuit_state"
        case circuitOpenUntil = "circuit_open_until"
        case consecutiveFailures = "consecutive_failures"
        case servers
        case authConnected = "auth_connected"
        case accountLabel = "account_label"
        case credentialHint = "credential_hint"
        case credentialExpiresAt = "credential_expires_at"
        case authError = "auth_error"
        case credentialHelp = "credential_help"
        case credentialHelpURL = "credential_help_url"
        case toolsChanged = "tools_changed"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pluginId = try c.decode(String.self, forKey: .pluginId)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "mcp"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? pluginId
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "puzzlepiece.extension"
        authMode = try c.decodeIfPresent(String.self, forKey: .authMode) ?? "none"
        trust = try c.decodeIfPresent(String.self, forKey: .trust) ?? "verified"
        installed = try c.decodeIfPresent(Bool.self, forKey: .installed) ?? false
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? false
        removable = try c.decodeIfPresent(Bool.self, forKey: .removable) ?? (kind != "builtin")
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "not_installed"
        consentRequired = try c.decodeIfPresent(Bool.self, forKey: .consentRequired) ?? (kind != "builtin")
        consentAt = try c.decodeIfPresent(String.self, forKey: .consentAt)
        dataNotice = try c.decodeIfPresent(String.self, forKey: .dataNotice) ?? ""
        toolsCount = try c.decodeIfPresent(Int.self, forKey: .toolsCount) ?? 0
        syncStatus = try c.decodeIfPresent(String.self, forKey: .syncStatus)
        lastSyncedAt = try c.decodeIfPresent(String.self, forKey: .lastSyncedAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        circuitState = try c.decodeIfPresent(String.self, forKey: .circuitState)
        circuitOpenUntil = try c.decodeIfPresent(String.self, forKey: .circuitOpenUntil)
        consecutiveFailures = try c.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        servers = try c.decodeIfPresent([MCPServer].self, forKey: .servers) ?? []
        authConnected = try c.decodeIfPresent(Bool.self, forKey: .authConnected)
        accountLabel = try c.decodeIfPresent(String.self, forKey: .accountLabel)
        credentialHint = try c.decodeIfPresent(String.self, forKey: .credentialHint)
        credentialExpiresAt = try c.decodeIfPresent(String.self, forKey: .credentialExpiresAt)
        authError = try c.decodeIfPresent(String.self, forKey: .authError)
        credentialHelp = try c.decodeIfPresent(String.self, forKey: .credentialHelp)
        credentialHelpURL = try c.decodeIfPresent(String.self, forKey: .credentialHelpURL)
        toolsChanged = try c.decodeIfPresent([String].self, forKey: .toolsChanged) ?? []
    }
}

public struct PluginCatalogResponse: Decodable, Sendable {
    public let catalog: [Plugin]
}

public struct PluginsResponse: Decodable, Sendable {
    public let plugins: [Plugin]
}

public struct PluginToolsResponse: Decodable, Sendable {
    public let tools: [MCPTool]

    enum CodingKeys: String, CodingKey {
        case tools
    }
}

public struct PluginSyncResult: Decodable, Sendable {
    public let added: [String]
    public let changed: [String]
    public let removed: [String]
    public let plugin: Plugin

    enum CodingKeys: String, CodingKey {
        case added
        case changed
        case removed
        case plugin
    }
}

public struct PluginUninstallResult: Decodable, Sendable {
    public let ok: Bool
    public let removedTools: Int
    public let affectedBots: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case removedTools = "removed_tools"
        case affectedBots = "affected_bots"
    }
}

/// POST /api/plugins/{id}/accept-tool-changes（D7：一键接受定义已变化的工具）
public struct PluginAcceptChangesResult: Decodable, Sendable {
    public let accepted: [String]
    public let plugin: Plugin

    enum CodingKeys: String, CodingKey {
        case accepted
        case plugin
    }
}
