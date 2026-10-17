import ImageIO
import QuickLook
import SwiftUI
import UIKit
import VeraBotCore
import VeraBotNetworking

/// 仅显示上传进度与失败重试，不展示附件预览或发送确认。
struct ComposerAttachmentStatus: View {
    let model: ComposerAttachmentModel

    var body: some View {
        HStack(spacing: 10) {
            switch model.state {
            case .empty: EmptyView()
            case .uploading:
                ProgressView()
                Text("正在上传 \(model.completedCount)/\(model.totalCount)…")
            case .sending:
                ProgressView()
                Text("正在发送…")
            case .ready:
                ProgressView()
                Text("上传完成，等待对话可发送…")
            case .failed(let message):
                Text(message).foregroundStyle(.red).lineLimit(2)
                Button("重试") { model.retry() }
            }
            Spacer(minLength: 0)
            Button("取消", role: .cancel) { model.remove() }.disabled(model.state == .sending)
        }
        .font(.caption)
        .padding(10)
    }
}

/// 同一条消息内的多图叠放；点开后按选择顺序翻页。
struct MessageAttachments: View {
    let attachments: [Attachment]
    let api: any VeraBotAPI
    @State private var showGallery = false
    @State private var gallerySelection = 0

    private var images: [Attachment] { attachments.filter { !$0.isFile } }

    /// 多图缩略卡片按单图的 67.5% 展示（在上一版基础上再缩小 10%），各层复用正面卡片尺寸并填满。
    private func stackSize(for front: Attachment) -> CGSize {
        let width = min(240, max(120, CGFloat(front.width))) * 0.675
        return CGSize(width: width, height: width * CGFloat(min(max(front.aspectRatio, 0.3), 3.0)))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if images.count > 1, let front = images.first {
                let size = stackSize(for: front)
                VStack(alignment: .trailing, spacing: 10) {
                    ZStack {
                        ForEach(Array(images.prefix(3).enumerated().reversed()), id: \.element.id) { index, attachment in
                            AttachmentBubble(attachment: attachment, api: api, thumbnailSize: size,
                                             onOpen: { openGallery(at: index) })
                                .accessibilityLabel("第 \(index + 1) 张，共 \(images.count) 张图片")
                                .rotationEffect(.degrees(Double(index) * -4))
                                .offset(x: CGFloat(index) * -10.8, y: CGFloat(index) * 7.2)
                                .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                        }
                    }
                    .padding(.leading, 50.4).padding(.top, 7.2).padding(.bottom, 28.8)
                    Button { openGallery(at: 0) } label: {
                        Label("共 \(images.count) 张图片", systemImage: "square.stack")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(images) { AttachmentBubble(attachment: $0, api: api) }
            }
            ForEach(attachments.filter(\.isFile)) { AttachmentBubble(attachment: $0, api: api) }
        }
        .fullScreenCover(isPresented: $showGallery) {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    GeometryReader { geometry in
                        TabView(selection: $gallerySelection) {
                            ForEach(Array(images.enumerated()), id: \.element.id) { index, attachment in
                                AttachmentBubble(attachment: attachment, api: api,
                                                 displayWidth: max(80, geometry.size.width - 16),
                                                 displayHeight: max(80, geometry.size.height))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                    Button("完成") { showGallery = false }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8).padding(.trailing, 12)
                }
                Text("\(gallerySelection + 1) / \(images.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("第 \(gallerySelection + 1) 张，共 \(images.count) 张图片")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8).padding(.bottom, 8)
            }
            .background(Color.appBackground)
        }
    }

    private func openGallery(at index: Int) {
        gallerySelection = index
        showGallery = true
    }
}

/// 消息气泡里的图片：始终显示真实图片（GIF 播放动画），点按用 Quick Look 全屏查看（自带分享）。
struct AttachmentBubble: View {
    @Environment(AppState.self) private var app
    let attachment: Attachment
    let api: any VeraBotAPI
    var displayWidth: CGFloat? = nil
    var displayHeight: CGFloat? = nil
    var thumbnailSize: CGSize? = nil
    var onOpen: (() -> Void)? = nil
    @State private var image: UIImage?
    @State private var data: Data?
    @State private var failed = false
    @State private var previewURL: URL?

    private static let maxWidth: CGFloat = 240
    private static let minWidth: CGFloat = 120

    var body: some View {
        let isPreview = thumbnailSize == nil && displayWidth != nil && !attachment.isFile
        let width = thumbnailSize?.width ?? displayWidth ?? (attachment.isFile ? Self.maxWidth : min(Self.maxWidth, max(Self.minWidth, CGFloat(attachment.width))))
        let height = thumbnailSize?.height ?? (attachment.isFile ? 88 : (isPreview ? displayHeight : nil) ?? min(720, width * CGFloat(min(max(attachment.aspectRatio, 0.3), 3.0))))
        let cornerRadius: CGFloat = isPreview ? 0 : 18
        ZStack {
            if attachment.isFile {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(attachment.filename ?? "文件").font(.subheadline.weight(.medium)).lineLimit(2)
                        Text("\((attachment.ext ?? "FILE").uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.bytes), countStyle: .file))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(width: 240, alignment: .leading)
                .background(Color.botBubble)
            } else if let image {
                // UIImageView 在明确的容器尺寸内执行等比缩放，静态图 / GIF 使用相同规则。
                // 缩略图填满并裁切；查看页完整等比显示，不裁切图片四角。
                AnimatedImageView(image: image, contentMode: isPreview ? .scaleAspectFit : .scaleAspectFill)
                    .frame(width: width, height: height)
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("图片已删除或无法加载").font(.caption)
                    Button("重试") { Task { await load() } }.font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(8)
            } else {
                VStack(spacing:8) {
                    Image(systemName:"photo")
                    Text(app.libraryDownloads?.active.contains(attachment.id) == true ? "正在下载…":"图片尚未下载").font(.caption)
                    Button("下载原件") { Task { await load(userInitiated:true) } }.font(.caption)
                }.foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .background(isPreview ? Color.clear : Color.botBubble)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            if let onOpen { onOpen() } else { openPreview() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attachment.isGIF ? "动图" : "图片")
        .accessibilityHint("点按全屏查看")
        .accessibilityAddTraits(.isButton)
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { old, new in
            if new == nil, let old, old.path.hasPrefix(AttachmentPreviewFiles.directory.path) { AttachmentPreviewFiles.remove(old) }
        }
        .task(id: attachment.id) { await load() }
        .onChange(of:app.libraryDownloads?.revision) { _,_ in if data==nil {Task {await load()}} }
    }

    private func load(userInitiated: Bool = false) async {
        failed = false
        do {
            let bytes: Data
            if !attachment.isFile, let cached = AttachmentImageStore.shared.cached(attachment.id) {
                bytes = cached
            } else {
                guard let url = await app.libraryDownloads?.prepare(id: attachment.id, userInitiated: userInitiated) else { return }
                bytes = try Data(contentsOf: url)
            }
            if attachment.isFile { data = bytes; return }
            let decoded = await Task.detached(priority: .userInitiated) {
                DecodedImage(image: AttachmentImageDecoder.image(from: bytes))
            }.value
            data = bytes
            image = decoded.image
            failed = decoded.image == nil
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }

    private func openPreview() {
        if let url=app.libraryDownloads?.localURL(id:attachment.id) { previewURL=url;return }
        guard let data else { Task {await load(userInitiated:true)};return }
        previewURL = AttachmentPreviewFiles.write(data, id: attachment.id, ext: attachment.isFile ? (attachment.ext ?? "txt") : nil)
    }
}

/// 后台解码结果跨回主 actor：UIImage 解码后不再修改，包一层显式标为 Sendable（与 SDK 版本无关，编译稳定）。
struct DecodedImage: @unchecked Sendable {
    let image: UIImage?
}

/// GIF：系统 ImageIO 逐帧解码 + UIImage.animatedImage；其他格式直接 UIImage(data:)。
enum AttachmentImageDecoder {
    static func image(from data: Data) -> UIImage? {
        guard AttachmentLimits.isGIF(data), let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: frame))
            duration += frameDelay(source, index)
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        return UIImage.animatedImage(with: frames, duration: duration > 0 ? duration : Double(frames.count) * 0.1)
    }

    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return delay < 0.02 ? 0.1 : delay   // 与浏览器一致：过小的帧间隔按 0.1 秒
    }
}

/// UIImageView 播放动图（SwiftUI Image 不播放 GIF）。系统「减弱动态效果」打开时只显示第一帧。
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    var contentMode: UIView.ContentMode = .scaleAspectFill

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = contentMode
        let shown = UIAccessibility.isReduceMotionEnabled ? (image.images?.first ?? image) : image
        if view.image !== shown { view.image = shown }
    }
}
