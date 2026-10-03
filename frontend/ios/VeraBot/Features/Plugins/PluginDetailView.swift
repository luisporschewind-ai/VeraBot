import SwiftUI
import VeraBotCore

/// 外部插件详情：状态、同意、按 Bot 开关工具、卸载。
struct PluginDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pluginID: String
    var promptConsent = false

    @State private var plugin: Plugin?
    @State private var tools: [MCPTool] = []
    @State private var bots: [Bot] = []
    @State private var botID: Int?
    @State private var allowed: [String] = []
    @State private var errorText: String?
    @State private var busy = false
    @State private var confirmUninstall = false
    @State private var showConsentPrompt = false
    @State private var didPrompt = false

    var body: some View {
        ThemedForm {
            if let plugin {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name).font(.headline)
                            Text("\(plugin.publisher) · \(plugin.version)").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: plugin.icon)
                    }
                    Text(plugin.description).font(.subheadline).foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("状态", value: plugin.stateTitle)
                    LabeledContent("同步", value: plugin.syncStatusText)
                    LabeledContent("上次同步", value: timeLabel(plugin.lastSyncedAt, empty: "尚未同步"))
                    LabeledContent("熔断", value: plugin.circuitText)
                    if plugin.circuitState == "open" {
                        LabeledContent("恢复时间", value: timeLabel(plugin.circuitOpenUntil, empty: "即将恢复"))
                    }
                    if plugin.consecutiveFailures > 0 {
                        LabeledContent("连续失败", value: "\(plugin.consecutiveFailures)")
                    }
                    if let lastError = plugin.lastError, !lastError.isEmpty {
                        Text(lastError).font(.footnote).foregroundStyle(.red)
                    }
                    CompactToggle("启用此插件", isOn: enabledBinding(plugin))
                        .disabled(busy)
                    Button("刷新工具") { Task { await refresh() } }
                        .disabled(busy || !plugin.enabled)
                } footer: {
                    Text(plugin.enabled ? "同步在后台进行。熔断打开时暂时不再连接这个插件。" : "停用后，这个插件的工具不会提供给任何 Bot。")
                }

                Section {
                    CompactToggle("同意把工具结果发送给 DeepSeek", isOn: consentBinding(plugin))
                        .disabled(busy)
                    LabeledContent("同意时间", value: timeLabel(plugin.consentAt, empty: "尚未同意"))
                } header: {
                    Text("数据与隐私")
                } footer: {
                    Text(plugin.dataNotice.isEmpty
                         ? "同意之后，它返回的内容会发送给 DeepSeek 用来生成回答。撤回后不再调用它的工具。"
                         : plugin.dataNotice)
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
                            .disabled(busy || !plugin.enabled)
                        ForEach(tools) { tool in
                            CompactToggle(isOn: toolBinding(tool)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.label)
                                    Text(tool.riskText).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .disabled(busy || !plugin.enabled || tool.status != "active")
                        }
                    }
                } header: {
                    Text("工具")
                } footer: {
                    Text("每个 Bot 最多 \(MCPToolRules.maxPerBot) 个插件工具。只读开关会保存成具体工具名。被其他 Bot 委派时不能使用这些工具。")
                }

                Section {
                    Button("卸载插件", role: .destructive) { confirmUninstall = true }
                        .disabled(busy || !plugin.removable)
                }
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .navigationTitle(plugin?.name ?? "插件")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("卸载「\(plugin?.name ?? "插件")」？", isPresented: $confirmUninstall, titleVisibility: .visible) {
            Button("卸载", role: .destructive) { Task { await uninstall() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会从所有 Bot 移除该插件的工具，并清除同意记录。重新安装后需要再次同意，并在每个 Bot 上重新开启。")
        }
        .alert("需要同意", isPresented: $showConsentPrompt) {
            Button("好", role: .cancel) {}
        } message: {
            Text("安装完成。同意把工具结果发送给 DeepSeek 之后，这个插件才会被调用。")
        }
        .task {
            if promptConsent && !didPrompt {
                didPrompt = true
                showConsentPrompt = true
            }
            await watch()
        }
    }

    private func timeLabel(_ iso: String?, empty: String) -> String {
        guard let date = ListTimestamp.parse(iso) else { return empty }
        return ListTimestamp.fullLabel(for: date)
    }

    private func watch() async {
        for _ in 0..<20 {
            await load()
            let waiting = plugin?.enabled == true && (plugin?.state == "syncing" || plugin?.syncStatus == "pending" || plugin?.syncStatus == "syncing")
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

    private func enabledBinding(_ plugin: Plugin) -> Binding<Bool> {
        Binding(get: { plugin.enabled }, set: { on in Task { await setEnabled(on) } })
    }

    private func consentBinding(_ plugin: Plugin) -> Binding<Bool> {
        Binding(get: { plugin.consented }, set: { on in Task { await setConsent(on) } })
    }

    private func toolBinding(_ tool: MCPTool) -> Binding<Bool> {
        Binding(get: { allowed.contains(tool.fullName) }, set: { on in
            Task { await setTool(tool, on: on) }
        })
    }

    private func load() async {
        do {
            plugin = try await app.api.plugin(id: pluginID)
            tools = try await app.api.pluginTools(id: pluginID).tools
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
            plugin = try await app.api.updatePlugin(id: pluginID, enabled: on)
            tools = try await app.api.pluginTools(id: pluginID).tools
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
            plugin = try await app.api.setPluginConsent(id: pluginID, granted: granted)
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            let synced = try await app.api.syncPlugin(id: pluginID)
            plugin = synced.plugin
            tools = try await app.api.pluginTools(id: pluginID).tools
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
                errorText = "每个 Bot 最多开启 \(MCPToolRules.maxPerBot) 个插件工具"
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
        await save(botID, MCPToolRules.addingReadOnly(current: allowed, tools: tools))
    }

    private func save(_ id: Int, _ names: [String]) async {
        busy = true
        defer { busy = false }
        do {
            let updated = try await app.api.updateBot(id, BotPatch(allowedTools: names))
            if let index = bots.firstIndex(where: { $0.id == id }) { bots[index] = updated }
            allowed = updated.allowedTools
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func uninstall() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await app.api.uninstallPlugin(id: pluginID)
            dismiss()
        } catch {
            errorText = app.message(for: error)
        }
    }
}

/// 内置插件只读详情。开关在 Bot 的「工具权限」里，这里只提供导航。
struct BuiltinPluginDetailView: View {
    @Environment(AppState.self) private var app
    let pluginID: String

    @State private var plugin: Plugin?
    @State private var bots: [Bot] = []
    @State private var errorText: String?

    private var toolRows: [(name: String, label: String)] {
        switch pluginID {
        case "builtin_weather": return [("get_weather", "天气查询")]
        case "builtin_reminder": return [("create_reminder", "创建提醒"), ("list_reminders", "查看提醒")]
        default: return []
        }
    }

    private var enabledBots: [Bot] {
        let names = Set(toolRows.map(\.name))
        return bots.filter { !Set($0.allowedTools).isDisjoint(with: names) }
    }

    var body: some View {
        ThemedForm {
            if let plugin {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name).font(.headline)
                            Text(plugin.publisher).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: plugin.icon)
                    }
                    Text(plugin.description)
                    if pluginID == "builtin_weather" {
                        LabeledContent("数据来源", value: "Open-Meteo")
                    }
                }

                Section {
                    if toolRows.isEmpty {
                        Text("没有工具").foregroundStyle(.secondary)
                    } else {
                        ForEach(toolRows, id: \.name) { tool in
                            Text(tool.label)
                        }
                    }
                } header: {
                    Text("所含工具")
                } footer: {
                    Text("内置插件无需安装，也不能卸载。是否让某个 Bot 使用它，在该 Bot 的「工具权限」里设置。")
                }

                Section {
                    if enabledBots.isEmpty {
                        Text("还没有 Bot 开启").foregroundStyle(.secondary)
                    } else {
                        ForEach(enabledBots) { bot in
                            Text(bot.name)
                        }
                    }
                } header: {
                    Text("已开启的 Bot")
                }

                Section {
                    NavigationLink {
                        BuiltinBotPermissionList(toolNames: toolRows.map(\.name))
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        Text("前往 Bot 的工具权限")
                    }
                }
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .navigationTitle(plugin?.name ?? "内置插件")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            plugin = try await app.api.plugin(id: pluginID)
            bots = try await app.api.bots().bots
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }
}

/// 选择一个 Bot，进入它的编辑页。工具开关在「工具权限」分组。
struct BuiltinBotPermissionList: View {
    @Environment(AppState.self) private var app
    let toolNames: [String]
    @State private var bots: [Bot] = []
    @State private var errorText: String?

    var body: some View {
        ThemedForm {
            Section {
                if bots.isEmpty {
                    Text("还没有 Bot").foregroundStyle(.secondary)
                }
                ForEach(bots) { bot in
                    NavigationLink {
                        BotEditView(bot: bot, onSaved: { _ in })
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        LabeledContent(bot.name) {
                            if !Set(bot.allowedTools).isDisjoint(with: Set(toolNames)) {
                                Text("已开启").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("进入 Bot 后，在「工具权限」里打开或关闭。")
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .navigationTitle("选择 Bot")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            bots = try await app.api.bots().bots
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }
}
