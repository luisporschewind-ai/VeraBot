import PhotosUI
import SwiftUI
import VeraBotCore
import VeraBotNetworking

/// 输入栏里待发送的图片（每条消息最多 1 张）：选图 → 本机压缩 → 上传拿 id → 随消息发送。
/// 上传中或失败时不能发送；再次选图会替换当前这张（未发送的旧图从服务器删掉）。
@MainActor
@Observable
final class ComposerAttachmentModel {
    enum State: Equatable {
        case empty
        case preparing
        case uploading
        case ready(Attachment)
        case failed(String)
    }

    private(set) var state: State = .empty
    /// 缩略图：GIF 为逐帧动图（与气泡同一解码器），其他格式为静态图。
    private(set) var preview: UIImage?
    private var prepared: PreparedImage?
    private var preparedFile: Data?
    private var preparedFilename: String?
    private var task: Task<Void, Never>?
    private let botID: Int
    private let api: any VeraBotAPI

    init(botID: Int, api: any VeraBotAPI) {
        self.botID = botID
        self.api = api
    }

    var isEmpty: Bool { state == .empty }
    var isBusy: Bool { state == .preparing || state == .uploading }
    /// 有图但还不能发（处理中 / 上传中 / 失败）
    var blocksSend: Bool {
        switch state {
        case .preparing, .uploading, .failed: true
        case .empty, .ready: false
        }
    }

    /// 待发送的是 GIF：缩略图用 `AnimatedImageView` 播放（与对话气泡一致）。
    var isGIF: Bool { prepared?.mime == "image/gif" }
    var pendingFilename: String? { preparedFilename }

    var ready: Attachment? {
        if case .ready(let attachment) = state { return attachment }
        return nil
    }

    func pick(_ item: PhotosPickerItem) {
        start { try await item.loadTransferable(type: Data.self) }
    }

    /// 拍照（系统相机）：先编码成 JPEG 原始数据（方向写在 EXIF 里，由 ImagePreparer 转正），
    /// 再走与相册相同的压缩路径（长边 2048、JPEG 0.8、重新写出不带 EXIF / GPS）；拍新照片同样替换当前这张。
    func pick(_ photo: UIImage) {
        start { photo.jpegData(compressionQuality: 1) }
    }

    func pickFile(_ url: URL) {
        discardUploaded(); task?.cancel(); state = .preparing; preview = nil; prepared = nil
        task = Task { [weak self] in
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                if let size = values.fileSize, size > AttachmentLimits.maxBytes { throw CocoaError(.fileReadTooLarge) }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                guard data.count <= AttachmentLimits.maxBytes else { throw CocoaError(.fileReadTooLarge) }
                let name = url.lastPathComponent
                guard ["pdf", "txt", "md", "csv", "docx", "xlsx"].contains(url.pathExtension.lowercased()) else {
                    throw NSError(domain: "VeraBotAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: "支持 PDF、TXT、MD、CSV、DOCX 和 XLSX 文件"])
                }
                guard let self else { return }
                self.preparedFile = data; self.preparedFilename = name
                await self.upload()
            } catch { self?.fail(error.localizedDescription) }
        }
    }

    private func start(_ load: @escaping @MainActor () async throws -> Data?) {
        discardUploaded()
        task?.cancel()
        state = .preparing
        preview = nil
        prepared = nil
        task = Task { [weak self] in
            do {
                guard let raw = try await load() else {
                    self?.fail(ImagePreparer.Failure.unreadable.localizedDescription)
                    return
                }
                // 压缩和缩略图解码都在后台；GIF 逐帧解码成动图（UIImage(data:) 只有第一帧，缩略图会不动）。
                let (image, preview) = try await Task.detached(priority: .userInitiated) {
                    let image = try ImagePreparer.prepare(raw)
                    return (image, DecodedImage(image: AttachmentImageDecoder.image(from: image.data)))
                }.value
                guard let self, !Task.isCancelled else { return }
                self.prepared = image
                self.preview = preview.image
                await self.upload()
            } catch is CancellationError {
                return
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    func retry() {
        guard prepared != nil || preparedFile != nil else { return }
        task?.cancel()
        task = Task { [weak self] in await self?.upload() }
    }

    /// 移除（未发送的图同时从服务器删除）
    func remove() {
        task?.cancel()
        discardUploaded()
        reset()
    }

    /// 发送时取走已上传的图：本机字节放进图片缓存，气泡立即显示，不再下载。
    func consume() -> Attachment? {
        guard let attachment = ready else { return nil }
        if let prepared { AttachmentImageStore.shared.put(attachment.id, data: prepared.data) }
        reset()
        return attachment
    }

    private func upload() async {
        guard let prepared, preparedFile == nil else {
            guard let data = preparedFile, let filename = preparedFilename else { return }
            state = .uploading
            do {
                let result = try await api.uploadAttachment(data: data, mime: "application/octet-stream", botID: botID, filename: filename)
                guard !Task.isCancelled else { return }
                state = .ready(result)
            } catch { guard !Task.isCancelled else { return }; fail(error.localizedDescription) }
            return
        }
        state = .uploading
        do {
            let attachment = try await api.uploadAttachment(data: prepared.data, mime: prepared.mime, botID: botID, filename: nil)
            guard !Task.isCancelled else { return }
            state = .ready(attachment)
        } catch {
            guard !Task.isCancelled else { return }
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
    }

    private func reset() {
        state = .empty
        preview = nil
        prepared = nil
        preparedFile = nil; preparedFilename = nil
        task = nil
    }

    private func discardUploaded() {
        guard let id = ready?.id else { return }
        let api = self.api
        Task { _ = try? await api.deleteAttachment(id: id) }
    }
}
