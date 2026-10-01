import SwiftUI
import VeraBotCore

/// 工具调用 / 多 Agent 交接的 trace 行。
struct TraceView: View {
    let trace: ToolTrace
    let fromBot: String

    private var pending: Bool { trace.result == nil }
    private var errorText: String? { trace.result?["error"]?.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.footnote.bold())
                if pending { ProgressView().controlSize(.mini) }
            }
            if trace.name == "ask_bot" {
                Text("问：\(trace.args?["question"]?.text ?? "")").font(.caption)
                let shared = trace.args?["shared_context"]?.text ?? ""
                Text(shared.isEmpty ? "未共享额外上下文（默认隔离）" : "共享背景：\(shared)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                if let answer = trace.result?["answer"]?.text {
                    Text(MessageMarkdown.inline("↩ **\(trace.result?["to_bot"]?.text ?? "")**：\(answer)"))
                        .font(.caption).lineLimit(8)
                        .padding(6)
                        .background(Color.insetFill, in: RoundedRectangle(cornerRadius: 8))
                    let tokens = trace.result?["tokens"]?.text ?? ""
                    let truncated = trace.result?["shared_truncated"]?.text == "true"
                    Text("协作记录 #\(trace.result?["delegation_id"]?.text ?? "-")" + (tokens.isEmpty ? "" : " · \(tokens) tokens")
                         + (truncated ? " · 共享背景已截断" : ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if !pending {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            if let errorText { Text("⚠️ \(errorText)").font(.caption).foregroundStyle(.orange) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(trace.name == "ask_bot" ? Color.brandSoft : Color.traceFill,
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private var title: String {
        switch trace.name {
        case "ask_bot": return "🤝 \(fromBot) → \(trace.args?["bot_name"]?.text ?? "?")"
        case "get_weather": return "🌤 天气查询"
        case "create_reminder": return "⏰ 创建提醒"
        case "list_reminders": return "📋 查看提醒"
        case "remember": return "🧠 记忆"
        case "forget_memory": return "🧠 忘掉记忆"
        default: return "🔧 \(trace.name)"
        }
    }

    private var summary: String {
        guard let r = trace.result, errorText == nil else { return "" }
        switch trace.name {
        case "get_weather":
            let c = r["current"]
            var s = "\(r["location"]?.text ?? "")：\(c?["weather"]?.text ?? "")，\(c?["temp_c"]?.text ?? "")°C"
            for d in r["forecast"]?.arrayValue ?? [] {
                s += "\n\(d["label"]?.text ?? d["date"]?.text ?? "") \(d["weather"]?.text ?? "") \(d["min_c"]?.text ?? "")~\(d["max_c"]?.text ?? "")°C"
            }
            return s
        case "create_reminder":
            return "已保存：\(r["content"]?.text ?? "") \(r["due_at"]?.text ?? "")"
        case "list_reminders":
            return "共 \(r["count"]?.text ?? "0") 条未完成提醒"
        default:
            return r.text
        }
    }
}
