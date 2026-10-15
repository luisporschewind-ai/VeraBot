import SwiftUI
import VeraBotCore

struct LibraryFileList: View {
    @Environment(AppState.self) private var app
    let items: [VeraBotCore.LibraryItem]
    var botID: Int? = nil
    var body: some View {
        LazyVStack(spacing:0) {
            ForEach(items) { item in
                NavigationLink { LibraryItemDetailView(item:item) } label: {
                    LibraryFileRow(item:item).padding(.vertical,12)
                }.buttonStyle(.plain)
                .contextMenu {
                    if let botID { Button("从当前 Bot 移除",systemImage:"minus.circle") { Task { try? await app.libraryRepository?.unlink(id:item.id,botID:botID);await app.refreshLibrary() } } }
                }
                if item.id != items.last?.id { Divider().padding(.leading,40) }
            }
        }
    }
}
struct LibraryFileRow: View {
    @Environment(AppState.self) private var app
    let item: VeraBotCore.LibraryItem
    var body: some View {
        HStack(spacing:12) {
            Image(systemName:item.isImage ? "photo":"doc.text").font(.title2).foregroundStyle(.secondary).frame(width:28)
            VStack(alignment:.leading,spacing:5) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(ByteCountFormatter.string(fromByteCount:Int64(item.bytes),countStyle:.file)) · \(item.sources.first?.displayName ?? "资料库") · \(String(item.createdAt.prefix(10)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
            if app.libraryDownloads?.localURL(id:item.id) != nil { Image(systemName:"checkmark.circle").foregroundStyle(.secondary).accessibilityLabel("已下载") }
            else if app.libraryDownloads?.active.contains(item.id) == true { ProgressView() }
            else { Image(systemName:item.availability=="available" ? "icloud.and.arrow.down":"exclamationmark.icloud").foregroundStyle(.secondary) }
            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}
