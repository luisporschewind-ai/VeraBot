import SwiftUI
import ImageIO
import QuickLook
import VeraBotCore

struct LibraryImageGrid: View {
    let items: [VeraBotCore.LibraryItem]
    @Environment(AppState.self) private var app
    @State private var previewURL: URL?
    @State private var details: VeraBotCore.LibraryItem?
    @State private var openingID: String?
    @State private var previewTask: Task<Void, Never>?
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var dates: [String] { Array(Set(items.map {String($0.createdAt.prefix(10))})).sorted(by:>) }
    var body: some View {
        LazyVStack(alignment:.leading,spacing:12) {
            ForEach(dates,id:\.self) { date in
                Text(date).font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:typeSize.isAccessibilitySize ? 2:3),spacing:4) {
                    ForEach(items.filter { $0.createdAt.hasPrefix(date) }) { item in
                        Button { openImage(item) } label: {
                            LibraryImageTile(item:item)
                                .overlay { if openingID == item.id { ProgressView().allowsHitTesting(false) } }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("资料详情", systemImage: "info.circle") {
                                guard openingID == nil, previewURL == nil else { return }
                                details = item
                            }
                        }
                    }
                }
            }
        }
        .quickLookPreview($previewURL)
        .sheet(item: $details) { LibraryImageDetailsSheet(item: $0) }
        .onDisappear { previewTask?.cancel() }
        .alert("无法查看图片", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private func openImage(_ item: VeraBotCore.LibraryItem) {
        guard openingID == nil, previewURL == nil, details == nil else { return }
        openingID = item.id
        previewTask = Task {
            defer { openingID = nil; previewTask = nil }
            do {
                let url = try await app.libraryDownloads?.previewURL(item: item)
                guard !Task.isCancelled else { return }
                if let url { previewURL = url }
                else { error = "图片暂不可用，请稍后重试。" }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

private struct LibraryImageDetailsSheet: View {
    let item: VeraBotCore.LibraryItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            LibraryItemDetailView(item: item)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        DismissToolbarButton(kind: .close) { dismiss() }
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
