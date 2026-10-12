import SwiftUI
import VeraBotCore

/// 真实查询来源；保留在历史消息中，链接由后端工具结果提供。
struct WebSourcesView: View {
    let sources: [WebSource]

    var body: some View {
        if !sources.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sources) { source in
                        VStack(alignment: .leading, spacing: 3) {
                            Link(destination: source.url) {
                                Text((source.citationNumber.map { "[\($0)] " } ?? "") + source.title)
                                    .font(.footnote).multilineTextAlignment(.leading)
                            }
                            Text(source.publisher).font(.caption2).foregroundStyle(.secondary)
                            Text(source.publishedAt.map { "发布时间：\($0)" } ?? "发布时间未提供")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let queried = source.queriedAt {
                                Text("查询：\(timeLabel(queried))" + (source.cacheHit ? " · 缓存" : ""))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if source.cacheHit, let fetched = source.fetchedAt {
                                Text("获取：\(timeLabel(fetched))").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(.top, 6)
            } label: {
                Label("参考来源（\(sources.count)）", systemImage: "link")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.traceFill, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func timeLabel(_ raw: String) -> String {
        guard let date = ListTimestamp.parse(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
