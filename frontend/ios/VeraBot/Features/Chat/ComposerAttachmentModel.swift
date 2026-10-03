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
    private(set) var preview: UIImage?
    private var prepared: PreparedImage?
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

    var ready: Attachment? {
        if case .ready(let attachment) = state { return attachment }
        return nil
    }

    func pick(_ item: PhotosPickerItem) {
        discardUploaded()
        task?.cancel()
        state = .preparing
        preview = nil
        prepared = nil
        task = Task { [weak self] in
            do {
                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    self?.fail(ImagePreparer.Failure.unreadable.localizedDescription)
                    return
                }
                let image = try await Task.detached(priority: .userInitiated) { try ImagePreparer.prepare(raw) }.value
                guard let self, !Task.isCancelled else { return }
                self.prepared = image
                self.preview = UIImage(data: image.data)
                await self.upload()
            } catch is CancellationError {
                return
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }

    func retry() {
        guard prepared != nil else { return }
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
        guard let prepared else { return }
        state = .uploading
        do {
            let attachment = try await api.uploadAttachment(data: prepared.data, mime: prepared.mime, botID: botID)
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
        task = nil
    }

    private func discardUploaded() {
        guard let id = ready?.id else { return }
        let api = self.api
        Task { _ = try? await api.deleteAttachment(id: id) }
    }
}
