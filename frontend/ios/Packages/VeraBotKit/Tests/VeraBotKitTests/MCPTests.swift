import Foundation
import Testing
@testable import VeraBotCore

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private func tool(_ id: Int, _ name: String, risk: String = "read", status: String = "active") throws -> MCPTool {
    try decode(MCPTool.self, """
    {"id":\(id),"server_id":1,"full_name":"mcp__learn__\(name)","mcp_name":"\(name)","label":"L","description":"",
     "risk":"\(risk)","requires_confirmation":\(risk != "read"),"delegable":false,"status":"\(status)",
     "annotations":{"readOnlyHint":true}}
    """)
}

@Test func mcpServerDecodesBackendPayloadWithoutURL() throws {
    let s = try decode(MCPServer.self, """
    {"id":1,"slug":"learn","catalog_id":"microsoft_learn","name":"Microsoft Learn","source":"catalog",
     "transport":"streamable_http","trust":"verified","auth_type":"none","status":"connected","enabled":true,
     "account_label":null,"tools_count":3,"last_error":null,"last_synced_at":"2026-10-03T05:00:00Z"}
    """)
    #expect(s.statusText == "已连接" && s.toolsCount == 3 && s.enabled && s.catalogId == "microsoft_learn")
}

@Test func mcpCatalogAndSyncDecodeIgnoringExtraKeys() throws {
    let c = try decode(MCPCatalogResponse.self, """
    {"catalog":[{"catalog_id":"aws_knowledge","slug":"aws","name":"AWS Knowledge","description":"d","trust":"verified",
     "transport":"streamable_http","auth":"none","enabled_by_default":false,"url_configured":true}]}
    """)
    #expect(c.catalog.first?.urlConfigured == true && c.catalog.first?.enabledByDefault == false)
    let r = try decode(MCPSyncResult.self, """
    {"added":["mcp__learn__a"],"changed":[],"removed":[],"rejected":[{"name":"bad","reason":"name"}],
     "server":{"id":1,"slug":"learn","catalog_id":null,"name":"L","source":"catalog","transport":"streamable_http",
     "trust":"verified","auth_type":"none","status":"error","enabled":true,"account_label":null,"tools_count":0,
     "last_error":"MCP 服务超时","last_synced_at":null}}
    """)
    #expect(r.added == ["mcp__learn__a"] && r.server.statusText == "异常" && r.server.lastError == "MCP 服务超时")
}

@Test func toolInfoOldPayloadIsBuiltin() throws {
    let old = try decode(ToolInfo.self, #"{"name":"get_weather","label":"天气查询","description":"d","delegation":false}"#)
    #expect(!old.isMCP && old.source == nil)
    let mcp = try decode(ToolInfo.self, """
    {"name":"mcp__learn__microsoft_docs_search","label":"搜索微软文档","description":"d","delegation":false,"source":"mcp",
     "server":"Microsoft Learn","server_id":1,"risk":"read","requires_confirmation":false,"delegable":false,"status":"active"}
    """)
    #expect(mcp.isMCP && mcp.serverId == 1 && mcp.delegable == false)
}

@Test func addingReadOnlyKeepsBuiltinsSkipsWriteAndRespectsCap() throws {
    let tools = [try tool(1, "a"), try tool(2, "w", risk: "write"), try tool(3, "gone", status: "removed"), try tool(4, "b")]
    let next = MCPToolRules.addingReadOnly(current: ["get_weather", "mcp__learn__a"], tools: tools)
    #expect(next == ["get_weather", "mcp__learn__a", "mcp__learn__b"])
    let full = (0..<MCPToolRules.maxPerBot).map { "mcp__x__t\($0)" }
    #expect(MCPToolRules.addingReadOnly(current: full, tools: tools) == full)
}

@Test func mcpTraceTitleUsesChineseLabelsAndNeverRawText() {
    #expect(MCPTraceText.title(for: "mcp__learn__microsoft_docs_search") == "🔌 Microsoft Learn · 搜索微软文档")
    #expect(MCPTraceText.title(for: "mcp__aws__aws___list_regions") == "🔌 AWS Knowledge · 列出 AWS 区域")
    #expect(MCPTraceText.title(for: "mcp__other__thing") == "🔌 other · thing")
    #expect(MCPTraceText.title(for: "get_weather") == nil)
    #expect(MCPTraceText.summary(contentLength: 8100, truncated: true).contains("已截断"))
    // 工具自身错误的 error 字段是外部原文，界面只给固定说明；权限拒绝等短文案照常显示
    #expect(MCPTraceText.errorText(code: "mcp_tool_error", error: "<untrusted_tool_result>…") == "外部服务返回了错误")
    #expect(MCPTraceText.errorText(code: "mcp_timeout", error: "MCP 服务超时") == "外部服务超时")
    #expect(MCPTraceText.errorText(code: "tool_not_allowed", error: "当前 Bot 未被授权使用该能力") == "当前 Bot 未被授权使用该能力")
}
