import SwiftUI
import VeraBotCore

struct QuotaView: View {
    @Environment(AppState.self) private var app
    @State private var quota: Quota?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let q = quota {
                    Section("今日 Token 额度") {
                        ProgressView(value: Double(min(q.today.totalTokens, q.dailyTokenQuota)),
                                     total: Double(max(q.dailyTokenQuota, 1)))
                        Text("\(q.today.totalTokens) / \(q.dailyTokenQuota) tokens · 今日请求 \(q.today.requests) 次")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("累计") {
                        LabeledContent("请求次数", value: "\(q.total.requests)")
                        LabeledContent("输入 Tokens", value: "\(q.total.promptTokens)")
                        LabeledContent("输出 Tokens", value: "\(q.total.completionTokens)")
                        LabeledContent("总 Tokens", value: "\(q.total.totalTokens)")
                        LabeledContent("Bot 间协作次数", value: "\(q.delegations)")
                        if let t = q.transcribe {
                            LabeledContent("语音转写（今日 / 累计）", value: "\(t.today.requests) / \(t.total.requests)")
                            LabeledContent("语音时长累计", value: "\(Int(t.total.seconds.rounded())) 秒")
                        }
                        LabeledContent("模型", value: q.model)
                    }
                    Section("近 7 日 Tokens") {
                        let maxTokens = max(q.daily.map(\.tokens).max() ?? 1, 1)
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(q.daily) { d in
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.brandLight)
                                        .frame(height: max(2, 100 * CGFloat(d.tokens) / CGFloat(maxTokens)))
                                    Text(d.date).font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 124, alignment: .bottom)
                    }
                    Section("按 Bot 统计") {
                        ForEach(q.perBot) { b in
                            HStack {
                                BotAvatar(emoji: b.avatar, color: b.color, size: 30)
                                Text(b.name)
                                Spacer()
                                Text("\(b.requests) 次 · \(b.totalTokens) tokens").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
            .navigationTitle("用量看板")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            quota = try await app.api.quota()
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }
}
