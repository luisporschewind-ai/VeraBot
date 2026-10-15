import SwiftUI
import ImageIO
import VeraBotCore

struct LibraryImageGrid: View {
    let items: [VeraBotCore.LibraryItem]
    @Environment(\.dynamicTypeSize) private var typeSize
    private var dates: [String] { Array(Set(items.map {String($0.createdAt.prefix(10))})).sorted(by:>) }
    var body: some View {
        LazyVStack(alignment:.leading,spacing:12) {
            ForEach(dates,id:\.self) { date in
                Text(date).font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:typeSize.isAccessibilitySize ? 2:3),spacing:4) {
                    ForEach(items.filter { $0.createdAt.hasPrefix(date) }) { item in
                        NavigationLink { LibraryItemDetailView(item:item) } label: { LibraryImageTile(item:item) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
struct LibraryImageTile: View {
    @Environment(AppState.self) private var app
    let item: VeraBotCore.LibraryItem
    @State private var preview: UIImage?
    @State private var previewFailed = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.secondary.opacity(0.08)
                if let preview { Image(uiImage:preview).resizable().scaledToFill() }
                else {
                    VStack(spacing: 8) {
                        Image(systemName: previewFailed ? "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90" : "photo")
                        if previewFailed { Text("预览暂不可用").font(.caption) }
                    }.foregroundStyle(.secondary)
                }
            }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
        }.aspectRatio(1,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:8))
        .accessibilityLabel(item.name)
        .task(id:app.libraryDownloads?.revision) {
            let url: URL
            do {
                guard let source = try await app.libraryDownloads?.previewURL(item: item) else { return }
                url = source
            } catch {
                if !Task.isCancelled { previewFailed = true }
                return
            }
            previewFailed = false
            preview=await Task.detached(priority:.utility) {
                guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:360,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return Optional<UIImage>.none }
                return UIImage(cgImage:image)
            }.value
        }
    }
}
