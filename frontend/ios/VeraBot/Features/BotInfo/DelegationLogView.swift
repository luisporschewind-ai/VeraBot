import SwiftUI
import VeraBotCore

/// 协作记录（Delegation log）
struct DelegationLogView: View {
    @Environment(AppState.self) private var app
    let bot: Bot
    @State private var records: [DelegationRecord] = []
    @State private var errorText: String?
    @State private var loaded = false

    var body: some View {
        List {
            ForEach(records) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(r.fromAvatar ?? "🤖") \(r.fromBot ?? "已删除") → \(r.toAvatar ?? "🤖") \(r.toBot ?? "已删除")")
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
                    Text("\(String((r.createdAt ?? "").prefix(16)).replacingOccurrences(of: "T", with: " ")) UTC · 深度 \(r.depth ?? 1) · \(r.totalTokens ?? 0) tokens")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .overlay {
            if loaded && records.isEmpty && errorText == nil {
                ContentUnavailableView("暂无协作记录", systemImage: "person.2.wave.2",
                                       description: Text("当该 Bot 委派或被委派时，记录会显示在这里"))
            }
        }
        .navigationTitle("\(bot.avatar) 协作记录")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func reasonText(_ r: String) -> String {
        switch r {
        case "not_in_allowlist": return "不在委派白名单"
        case "target_refuses": return "对方不接受委派"
        case "loop": return "检测到委派环路"
        case "turn_cap": return "超过单轮委派次数上限"
        case "budget": return "Token 额度已用完"
        case "self": return "不能委派给自己"
        default: return r
        }
    }

    private func load() async {
        do {
            records = try await app.api.delegations(botID: bot.id).delegations
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
        loaded = true
    }
}
