import Foundation
import Testing
@testable import VeraBotCore

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private let learnJSON = """
{"plugin_id":"microsoft_learn","kind":"mcp","name":"Microsoft Learn","description":"查询微软官方技术文档与代码示例。",
 "category":"知识与文档","publisher":"Microsoft","version":"1.0.0","icon":"book.closed","auth_mode":"none",
 "trust":"verified","installed":true,"available":true,"removable":true,"enabled":true,"state":"needs_consent",
 "consent_required":true,"consent_at":null,"data_notice":"工具返回的内容会发送给 DeepSeek 用来生成回答。",
 "tools_count":3,"sync_status":"ok","last_synced_at":"2026-10-03T08:12:00+00:00","last_error":null,
 "circuit_state":"closed","circuit_open_until":null,"consecutive_failures":0,
 "servers":[{"id":1,"slug":"learn","catalog_id":"microsoft_learn","name":"Microsoft Learn","source":"catalog",
  "transport":"streamable_http","trust":"verified","auth_type":"none","status":"connected","enabled":true,
  "account_label":null,"tools_count":3,"last_error":null,"last_synced_at":"2026-10-03T08:12:00+00:00",
  "consent_at":null,"sync_status":"ok","circuit_state":"closed","circuit_open_until":null,"consecutive_failures":0}],
 "extra_future_field":1}
"""

@Test func pluginDecodesAndIgnoresUnknownKeys() throws {
    let plugin = try decode(Plugin.self, learnJSON)
    #expect(plugin.pluginId == "microsoft_learn")
    #expect(plugin.stateTitle == "待同意")
    #expect(!plugin.consented)
    #expect(plugin.servers.count == 1)
    #expect(plugin.servers[0].slug == "learn")
}

@Test func pluginStateTitlesMatchBackendOrder() throws {
    let titles = [
        "disabled": "已停用",
        "circuit_open": "已熔断",
        "syncing": "正在同步",
        "error": "同步失败",
        "needs_consent": "待同意",
        "ready": "可用",
    ]
    for (state, title) in titles {
        let plugin = try decode(Plugin.self, learnJSON.replacingOccurrences(of: "\"needs_consent\"", with: "\"\(state)\""))
        #expect(plugin.stateTitle == title)
    }
}

@Test func builtinPluginSubtitleAndMissingFields() throws {
    let plugin = try decode(Plugin.self, """
    {"plugin_id":"builtin_weather","kind":"builtin","name":"天气","description":"查询天气。数据来自 Open-Meteo。","state":"ready"}
    """)
    #expect(plugin.isBuiltin)
    #expect(plugin.stateTitle == "内置 · 无需安装")
    #expect(plugin.servers.isEmpty)
    #expect(plugin.toolsCount == 0)
    #expect(!plugin.removable)
}

@Test func pluginSyncAndUninstallDecode() throws {
    let synced = try decode(PluginSyncResult.self, """
    {"added":["mcp__learn__microsoft_docs_search"],"changed":[],"removed":[],"plugin":\(learnJSON)}
    """)
    #expect(synced.added == ["mcp__learn__microsoft_docs_search"])
    #expect(synced.plugin.state == "needs_consent")
    let removed = try decode(PluginUninstallResult.self, """
    {"ok":true,"removed_tools":3,"affected_bots":1}
    """)
    #expect(removed.ok && removed.removedTools == 3 && removed.affectedBots == 1)
}

@Test func toolInfoReadsPluginIdAndStaysCompatible() throws {
    let weather = try decode(ToolInfo.self, """
    {"name":"get_weather","label":"天气查询","description":"d","source":"builtin","plugin_id":"builtin_weather"}
    """)
    #expect(weather.pluginId == "builtin_weather" && !weather.isMCP)
    let ask = try decode(ToolInfo.self, """
    {"name":"ask_bot","description":"d","source":"builtin","plugin_id":null}
    """)
    #expect(ask.pluginId == nil)
    let old = try decode(ToolInfo.self, """
    {"name":"get_weather","description":"d"}
    """)
    #expect(old.pluginId == nil && !old.isMCP)
}

private let githubJSON = """
{"plugin_id":"github","kind":"mcp","name":"GitHub","auth_mode":"bearer","state":"needs_auth","installed":true,
 "available":true,"auth_connected":false,"account_label":null,"credential_hint":null,"credential_expires_at":null,
 "auth_error":"token_invalid","credential_help":"只选测试仓库","credential_help_url":"https://github.com/settings/personal-access-tokens/new",
 "tools_changed":["list_issues"]}
"""

@Test func connectorFieldsDecodeAndOldBackendDefaults() throws {
    let gh = try decode(Plugin.self, githubJSON)
    #expect(gh.needsToken)
    #expect(gh.stateTitle == "需要连接")
    #expect(gh.authConnected == false)
    #expect(gh.authErrorText == "令牌无效或已撤销")
    #expect(gh.toolsChanged == ["list_issues"])
    #expect(gh.credentialHelpURL?.hasPrefix("https://github.com/") == true)
    let old = try decode(Plugin.self, learnJSON)
    #expect(old.authConnected == nil && old.credentialHint == nil && old.authError == nil)
    #expect(old.toolsChanged.isEmpty && !old.needsToken && old.authErrorText == nil)
}

@Test func connectorAuthErrorTextsAndTrace() throws {
    let texts = ["expired": "授权已过期", "insufficient_scope": "权限不足", "network_unreachable": "网络不可达"]
    for (code, text) in texts {
        let p = try decode(Plugin.self, githubJSON.replacingOccurrences(of: "\"token_invalid\"", with: "\"\(code)\""))
        #expect(p.authErrorText == text)
    }
    #expect(MCPTraceText.errorText(code: "mcp_auth_required", error: nil) == "需要在插件页重新连接")
    #expect(MCPTraceText.errorText(code: "mcp_permission_denied", error: "raw") == "服务拒绝：令牌没有这个资源或这项权限")
    #expect(MCPTraceText.title(for: "mcp__github__list_issues") == "🔌 GitHub · 列出 issue")
    let accepted = try decode(PluginAcceptChangesResult.self, "{\"accepted\":[\"list_issues\"],\"plugin\":\(githubJSON)}")
    #expect(accepted.accepted == ["list_issues"])
}
