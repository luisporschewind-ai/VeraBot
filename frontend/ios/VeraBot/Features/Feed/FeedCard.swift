import SwiftUI
import VeraBotCore

struct FeedCard: View {
    let item: FeedItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let kind = FeedContentKind(rawValue: item.kind)
                Label(kind?.label ?? "内容", systemImage: kind?.symbol ?? "doc.text")
                Spacer()
                if item.read { Text("已读") }
                if item.saved { Image(systemName: "bookmark.fill").accessibilityLabel("已收藏") }
            }.font(.caption).foregroundStyle(.secondary)
            Text(item.title).font(.headline).foregroundStyle(.primary).lineLimit(3)
            Text(item.sourceName).font(.caption).foregroundStyle(.secondary)
            if !item.summary.isEmpty {
                Text(item.evidenceLabel).font(.caption2).foregroundStyle(.secondary)
                Text(item.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            if !item.recommendationReason.isEmpty {
                Text(item.recommendationReason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !item.recommendedBy.isEmpty {
                Text("供稿：" + item.recommendedBy.map(\.botName).joined(separator: "、"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 8)
    }
}
