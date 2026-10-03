import SwiftUI
import VeraBotCore

/// 设置 → 连接的账号 / MCP 服务。服务器开关按用户保存；工具开关按 Bot 保存。
struct MCPServicesSection: View {
    @Environment(AppState.self) private var app
    @State private var servers: [MCPServer] = []
    @State private var errorText: String?

    var body: some View {
        Section {
            if servers.isEmpty && errorText == nil {
                Text("正在读取 MCP 服务…").foregroundStyle(.secondary)
            }
            ForEach(servers) { server in
                NavigationLink {
                    MCPServerDetailView(serverID: server.id)
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    LabeledContent(server.name) {
                        Text(server.statusText)
                    }
                }
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("连接的账号 / MCP 服务")
        } footer: {
            Text("Microsoft Learn 默认开启，AWS Knowledge 默认关闭。工具按每个 Bot 单独开关，默认全部关闭。每个服务要单独同意后才会调用；工具返回的内容会发送给 DeepSeek 用来生成回答。")
        }
        .task { await watch() }
    }

    private func watch() async {
        for _ in 0..<20 {
            await reload()
            if !servers.contains(where: { $0.enabled && ($0.syncStatus == "pending" || $0.syncStatus == "syncing") }) {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
        }
    }

    private func reload() async {
        do {
            servers = try await app.api.mcpServers().servers
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }
}

struct MCPServerDetailView: View {
    @Environment(AppState.self) private var app
    let serverID: Int

    @State private var server: MCPServer?
    @State private var tools: [MCPTool] = []
    @State private var bots: [Bot] = []
    @State private var botID: Int?
    @State private var allowed: [String] = []
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        ThemedForm {
            if let server {
                Section {
                    LabeledContent("状态", value: server.statusText)
                    LabeledContent("同步", value: server.syncStatusText)
                    LabeledContent("上次同步", value: timeLabel(server.lastSyncedAt, empty: "尚未同步"))
                    LabeledContent("熔断", value: server.circuitText)
                    if server.circuitState == "open" {
                        LabeledContent("恢复时间", value: timeLabel(server.circuitOpenUntil, empty: "即将恢复"))
                    }
                    if let failures = server.consecutiveFailures, failures > 0 {
                        LabeledContent("连续失败", value: "\(failures)")
                    }
                    if let lastError = server.lastError, !lastError.isEmpty {
                        Text(lastError).font(.footnote).foregroundStyle(.red)
                    }
                    CompactToggle("启用此服务", isOn: enabledBinding(server))
                        .disabled(busy)
                    Button("刷新工具") { Task { await refresh() } }
                        .disabled(busy || !server.enabled)
                } footer: {
                    Text(server.enabled ? "同步在后台进行。熔断打开时暂时不再连接这个服务。" : "停用后，这个服务的工具不会提供给任何 Bot。")
                }

                Section {
                    CompactToggle("同意把工具结果发送给 DeepSeek", isOn: consentBinding(server))
                        .disabled(busy)
                    LabeledContent("同意时间", value: timeLabel(server.consentAt, empty: "尚未同意"))
                } footer: {
                    Text("同意只针对这个服务。同意之后，它返回的内容会发送给 DeepSeek 用来生成回答。撤回后不再调用它的工具。")
                }

                Section {
                    if bots.isEmpty {
                        Text("还没有 Bot").foregroundStyle(.secondary)
                    } else {
                        Picker("应用到 Bot", selection: botBinding) {
                            ForEach(bots) { bot in
                                Text(bot.name).tag(Optional(bot.id))
                            }
                        }
                        Button("开启全部只读") { Task { await enableReadOnly() } }
                            .disabled(busy || !server.enabled)
                        ForEach(tools) { tool in
                            CompactToggle(isOn: toolBinding(tool)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.label)
                                    Text(tool.riskText).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(busy || !server.enabled || tool.status != "active")
                        }
                    }
                } header: {
                    Text("工具")
                } footer: {
                    Text("每个 Bot 最多 \(MCPToolRules.maxPerBot) 个 MCP 工具。只读开关会保存成具体工具名。被其他 Bot 委派时不能使用这些工具。")
                }
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .navigationTitle(server?.name ?? "MCP 服务")
        .navigationBarTitleDisplayMode(.inline)
        .task { await watch() }
    }

    private func timeLabel(_ iso: String?, empty: String) -> String {
        guard let date = ListTimestamp.parse(iso) else { return empty }
        return ListTimestamp.fullLabel(for: date)
    }

    private func watch() async {
        for _ in 0..<20 {
            await load()
            let waiting = server?.enabled == true && (server?.syncStatus == "pending" || server?.syncStatus == "syncing")
            if !waiting { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
        }
    }

    private var botBinding: Binding<Int?> {
        Binding(get: { botID }, set: { id in
            botID = id
            allowed = bots.first { $0.id == id }?.allowedTools ?? []
        })
    }

    private func enabledBinding(_ server: MCPServer) -> Binding<Bool> {
        Binding(get: { server.enabled }, set: { on in Task { await setEnabled(on) } })
    }

    private func consentBinding(_ server: MCPServer) -> Binding<Bool> {
        Binding(get: { server.consented }, set: { on in Task { await setConsent(on) } })
    }

    private func toolBinding(_ tool: MCPTool) -> Binding<Bool> {
        Binding(get: { allowed.contains(tool.fullName) }, set: { on in
            Task { await setTool(tool, on: on) }
        })
    }

    private func load() async {
        do {
            let list = try await app.api.mcpServers().servers
            server = list.first { $0.id == serverID }
            tools = try await app.api.mcpTools(serverID: serverID).tools
            bots = try await app.api.bots().bots
            if botID == nil { botID = bots.first?.id }
            allowed = bots.first { $0.id == botID }?.allowedTools ?? []
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func setEnabled(_ on: Bool) async {
        busy = true
        defer { busy = false }
        do {
            server = try await app.api.updateMCPServer(id: serverID, enabled: on)
            tools = try await app.api.mcpTools(serverID: serverID).tools
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
        if on { await watch() }
    }

    private func setConsent(_ granted: Bool) async {
        busy = true
        defer { busy = false }
        do {
            server = try await app.api.setMCPConsent(id: serverID, granted: granted)
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            let synced = try await app.api.syncMCPServer(id: serverID)
            server = synced.server
            tools = try await app.api.mcpTools(serverID: serverID).tools
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func setTool(_ tool: MCPTool, on: Bool) async {
        guard let botID else { return }
        var next = allowed
        if on {
            if next.contains(tool.fullName) { return }
            if next.filter({ $0.hasPrefix("mcp__") }).count >= MCPToolRules.maxPerBot {
                errorText = "每个 Bot 最多开启 \(MCPToolRules.maxPerBot) 个 MCP 工具"
                return
            }
            next.append(tool.fullName)
        } else {
            next.removeAll { $0 == tool.fullName }
        }
        await save(botID, next)
    }

    private func enableReadOnly() async {
        guard let botID else { return }
        let next = MCPToolRules.addingReadOnly(current: allowed, tools: tools)
        await save(botID, next)
    }

    private func save(_ id: Int, _ tools: [String]) async {
        busy = true
        defer { busy = false }
        do {
            let updated = try await app.api.updateBot(id, BotPatch(allowedTools: tools))
            if let index = bots.firstIndex(where: { $0.id == id }) { bots[index] = updated }
            allowed = updated.allowedTools
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }
}
