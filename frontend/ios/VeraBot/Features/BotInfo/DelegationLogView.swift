import SwiftUI
import VeraBotCore

/// 协作记录：委派 + MCP 工具调用（M3）。时间按本机时区显示。
struct DelegationLogView: View {
    @Environment(AppState.self) private var app
    let bot: Bot
    @State private var records: [DelegationRecord] = []
    @State private var toolCalls: [ToolCallRecord] = []
    @State private var errorText: String?
    @State private var loaded = false

    var body: some View {
        ThemedList {
            if !records.isEmpty {
                Section("协作") {
                    ForEach(records) { r in
                        delegationRow(r)
                    }
                }
            }
            if !toolCalls.isEmpty {
                Section("工具调用") {
                    ForEach(toolCalls) { t in
                        toolRow(t)
                    }
                }
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .overlay {
            if loaded && records.isEmpty && toolCalls.isEmpty && errorText == nil {
                ContentUnavailableView("暂无记录", systemImage: "person.2.wave.2",
                                       description: Text("当该 Bot 委派、被委派或调用外部工具时，记录会显示在这里"))
            }
        }
        .navigationTitle("\(BotAvatarFigure.textLabel(stored: bot.avatar)) 协作记录")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private func delegationRow(_ r: DelegationRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(BotAvatarFigure.textLabel(stored: r.fromAvatar)) \(r.fromBot ?? "已删除") → \(BotAvatarFigure.textLabel(stored: r.toAvatar)) \(r.toBot ?? "已删除")")
                    .font(.subheadline.bold())
                Spacer()
                Text(r.status == "ok" ? "成功" : "已拒绝")
                    .font(.caption2.bold())
                    .foregroundStyle(r.status == "ok" ? Color.green : Color.orange)
            }
            Text("问：\(r.question)").font(.caption)
            if let sc = r.sharedContext, !sc.isEmpty {
                Text("共享背景：\(sc)" + ((r.sharedTruncated ?? 0) == 1 ? "（已截断）" : ""))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            } else {
                Text("未共享额外上下文").font(.caption2).foregroundStyle(.secondary)
            }
            if r.status == "ok", let a = r.answer, !a.isEmpty {
                Text("↩ \(a)").font(.caption).lineLimit(4)
            }
            if let reason = r.reason, !reason.isEmpty {
                Text("拒绝原因：\(reasonText(reason))").font(.caption).foregroundStyle(.orange)
            }
            Text("\(timeText(r.createdAt)) · 深度 \(r.depth ?? 1) · 用量 \(r.totalTokens ?? 0)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func toolRow(_ t: ToolCallRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(toolKindLabel(t.kind)).font(.subheadline.bold())
            if let tool = t.tool, !tool.isEmpty {
                Text(tool).font(.caption).lineLimit(1)
            }
            HStack {
                if let server = t.server?.displayText, server != "null" {
                    Text(server).font(.caption2).foregroundStyle(.secondary)
                }
                if let status = t.status {
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(timeText(t.createdAt)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func toolKindLabel(_ kind: String) -> String {
        switch kind {
        case "mcp_tool_call": return "工具调用"
        case "mcp_action_requested": return "待确认"
        case "mcp_action_confirmed": return "已确认执行"
        case "mcp_action_cancelled": return "已取消"
        case "mcp_action_expired": return "已过期"
        case "mcp_action_failed": return "执行失败"
        default: return kind
        }
    }

    private func timeText(_ iso: String?) -> String {
        guard let date = ListTimestamp.parse(iso) else { return "时间未知" }
        return ListTimestamp.fullLabel(for: date)
    }

    private func reasonText(_ r: String) -> String {
        switch r {
        case "not_in_allowlist": return "不在委派白名单"
        case "target_refuses": return "对方不接受委派"
        case "loop": return "检测到委派环路"
        case "turn_cap": return "超过单轮委派次数上限"
        case "budget": return "今日额度已用完"
        case "self": return "不能委派给自己"
        default: return r
        }
    }

    private func load() async {
        do {
            async let d = app.api.delegations(botID: bot.id)
            async let t = app.api.toolCalls(botID: bot.id)
            records = try await d.delegations
            toolCalls = (try? await t.toolCalls) ?? []
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
        loaded = true
    }
}
