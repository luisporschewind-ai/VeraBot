import ImageIO
import QuickLook
import SwiftUI
import UIKit
import VeraBotCore
import VeraBotNetworking

/// 输入栏上方的待发送图片：缩略图 + 状态 + 重试 / 移除。系统默认控件，无自定义动画。
struct ComposerAttachmentChip: View {
    let model: ComposerAttachmentModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if let preview = model.preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    Color.botBubble
                }
                if model.isBusy { ProgressView() }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            statusText
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 0)
            if case .failed = model.state {
                Button("重试") { model.retry() }
                    .font(.caption)
            }
            Button { model.remove() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除图片")
        }
        .padding(8)
        .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
    }

    @ViewBuilder private var statusText: some View {
        switch model.state {
        case .empty: EmptyView()
        case .preparing: Text("正在处理图片…").foregroundStyle(.secondary)
        case .uploading: Text("正在上传…").foregroundStyle(.secondary)
        case .ready: Text("图片已就绪，可直接发送").foregroundStyle(.secondary)
        case .failed(let message): Text(message).foregroundStyle(.red)
        }
    }
}

/// 消息气泡里的图片：始终显示真实图片（GIF 播放动画），点按用 Quick Look 全屏查看（自带分享）。
struct AttachmentBubble: View {
    let attachment: Attachment
    let api: any VeraBotAPI
    @State private var image: UIImage?
    @State private var data: Data?
    @State private var failed = false
    @State private var previewURL: URL?

    private static let maxWidth: CGFloat = 240
    private static let minWidth: CGFloat = 120

    var body: some View {
        let width = min(Self.maxWidth, max(Self.minWidth, CGFloat(attachment.width)))
        let height = width * CGFloat(min(max(attachment.aspectRatio, 0.3), 3.0))
        ZStack {
            if let image {
                if attachment.isGIF {
                    AnimatedImageView(image: image)
                } else {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("图片已删除或无法加载").font(.caption)
                    Button("重试") { Task { await load() } }.font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(8)
            } else {
                ProgressView()
            }
        }
        .frame(width: width, height: height)
        .background(Color.botBubble)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { openPreview() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attachment.isGIF ? "动图" : "图片")
        .accessibilityHint("点按全屏查看")
        .accessibilityAddTraits(.isButton)
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { old, new in
            if new == nil, let old { AttachmentPreviewFiles.remove(old) }
        }
        .task(id: attachment.id) { await load() }
    }

    private func load() async {
        failed = false
        do {
            let bytes = try await AttachmentImageStore.shared.load(attachment.id, api: api)
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
        guard let data else { return }
        previewURL = AttachmentPreviewFiles.write(data, id: attachment.id, isGIF: attachment.isGIF)
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

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        let shown = UIAccessibility.isReduceMotionEnabled ? (image.images?.first ?? image) : image
        if view.image !== shown { view.image = shown }
    }
}
