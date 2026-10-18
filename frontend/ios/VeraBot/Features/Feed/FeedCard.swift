import SwiftUI
import VeraBotCore

struct FeedCard: View {
    let item: FeedItem
    let bots: [Bot]
    let busy: Bool
    let preparing: Bool
    let open: () -> Void
    let discuss: (Bot) -> Void
    @State private var selectedBotID: Int?

    private var kind: FeedContentKind? { FeedContentKind(rawValue: item.kind) }
    private var discussionBot: Bot? {
        if let selectedBotID, let bot = bots.first(where: { $0.id == selectedBotID }) { return bot }
        let contributorIDs = Set(item.recommendedBy.map(\.botID) + [item.botID].compactMap { $0 })
        return bots.first(where: { contributorIDs.contains($0.id) }) ?? bots.first
    }
    private var accent: Color {
        switch item.kind { case "post": .teal; case "video": .indigo; case "audio": .orange; default: .blue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    switch item.kind {
                    case "post": postContent
                    case "video": videoContent
                    case "audio": audioContent
                    default: newsContent
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.05), lineWidth: 0.5) }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Label(kind?.label ?? "内容", systemImage: kind?.symbol ?? "doc.text")
                .font(.caption.weight(.semibold)).foregroundStyle(accent)
            Text(item.sourceName).lineLimit(1)
            Spacer(minLength: 0)
            if item.read { Text("已读").font(.caption2) }
            if item.saved { Image(systemName: "bookmark.fill").accessibilityLabel("已收藏") }
        }.font(.caption).foregroundStyle(.secondary)
    }

    private var newsContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.headline).foregroundStyle(.primary).lineLimit(3)
                excerpt(lines: 3)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let imageURL = safeImageURL {
                artwork(url: imageURL, symbol: "newspaper")
                    .frame(width: 92, height: 92).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var postContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let author = item.author, !author.isEmpty {
                Label(author, systemImage: "person.crop.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
            }
            if !item.summary.isEmpty {
                Text(item.summary).font(.body).foregroundStyle(.primary).lineLimit(6)
            } else { Text(item.title).font(.body).foregroundStyle(.primary).lineLimit(6) }
            if let imageURL = safeImageURL {
                artwork(url: imageURL, symbol: "photo")
                    .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var videoContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                artwork(url: safeImageURL, symbol: "video")
                Image(systemName: "play.fill").font(.title2)
                    .foregroundStyle(.white).padding(17).background(.black.opacity(0.45), in: Circle())
                    .accessibilityHidden(true)
            }
            .frame(height: 184).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) { mediaBadge.padding(9) }
            Text(item.title).font(.headline).foregroundStyle(.primary).lineLimit(3)
            excerpt(lines: 2)
        }
    }

    private var audioContent: some View {
        HStack(alignment: .top, spacing: 12) {
            artwork(url: safeImageURL, symbol: "waveform")
                .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 7) {
                Text(item.title).font(.headline).foregroundStyle(.primary).lineLimit(3)
                HStack(spacing: 7) {
                    Image(systemName: "headphones")
                    Text(durationLabel ?? "音频节目")
                    Text("· 原站收听")
                }.font(.caption).foregroundStyle(accent)
                excerpt(lines: 2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func excerpt(lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !item.summary.isEmpty {
                Text(item.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(lines)
                Text(item.evidenceLabel).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let date = item.publishedAt.flatMap(VeraBotDate.parse) {
                Text(date, style: .date).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let bot = discussionBot {
                Menu {
                    ForEach(bots) { option in Button(option.name) { selectedBotID = option.id } }
                } label: {
                    HStack(spacing: 4) {
                        LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                                      hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt, size: 24)
                            .allowsHitTesting(false)
                        Text(bot.name).font(.caption.weight(.medium)).lineLimit(1)
                    }
                }.accessibilityLabel("讨论 Bot：\(bot.name)，点击更换")
                .disabled(busy)
                Button { discuss(bot) } label: {
                    HStack(spacing: 5) {
                        if preparing { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "bubble.left.and.bubble.right") }
                        Text("Discuss")
                    }.font(.caption.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .background(Color.accentColor.opacity(0.10), in: Capsule())
                .disabled(busy)
                .accessibilityLabel("与\(bot.name)讨论：\(item.title)")
            } else {
                Label("暂无可用 Bot", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.buttonStyle(.borderless)
    }

    private var safeImageURL: URL? {
        guard let raw = item.imageURL, let url = URL(string: raw),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }
    private var durationLabel: String? {
        guard let seconds = item.durationSeconds else { return nil }
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                              : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    private var mediaBadge: some View {
        Text(durationLabel ?? "原站播放").font(.caption.weight(.medium)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 4).background(.black.opacity(0.65), in: Capsule())
    }
    private func artwork(url: URL?, symbol: String) -> some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(accent.opacity(0.45))
                if let url {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                        placeholder: { Color.clear }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}
