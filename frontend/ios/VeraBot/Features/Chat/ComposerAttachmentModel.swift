import PhotosUI
import SwiftUI
import VeraBotCore
import VeraBotNetworking

/// 一次选择作为一批发送；重试复用已上传的部分，不再展示发送前预览。
@MainActor
@Observable
final class ComposerAttachmentModel {
    enum State: Equatable {
        case empty
        case uploading
        case sending
        case ready([Attachment])
        case failed(String)
    }

    private struct Payload {
        let data: Data
        let mime: String
        let filename: String?
    }

    private(set) var state: State = .empty
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private var loaders: [@MainActor () async throws -> Payload] = []
    private var payloads: [Int: Payload] = [:]
    private var uploaded: [Attachment] = []
    private var task: Task<Void, Never>?
    private let botID: Int?
    private let api: any VeraBotAPI

    init(botID: Int?, api: any VeraBotAPI) {
        self.botID = botID
        self.api = api
    }

    var isEmpty: Bool { state == .empty }
    var isBusy: Bool { state == .uploading }
    var blocksSend: Bool { !isEmpty }
    var ready: [Attachment] {
        if case .ready(let attachments) = state { return attachments }
        return []
    }

    func pick(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, items.count <= AttachmentLimits.maxPerMessage, isEmpty else { return }
        start(items.map { item in
            {
                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    throw ImagePreparer.Failure.unreadable
                }
                let image = try await Task.detached(priority: .userInitiated) { try ImagePreparer.prepare(raw) }.value
                return Payload(data: image.data, mime: image.mime, filename: nil)
            }
        })
    }

    func pick(_ photo: UIImage) {
        guard isEmpty else { return }
        start([{
            guard let raw = photo.jpegData(compressionQuality: 1) else { throw ImagePreparer.Failure.unreadable }
            let image = try await Task.detached(priority: .userInitiated) { try ImagePreparer.prepare(raw) }.value
            return Payload(data: image.data, mime: image.mime, filename: nil)
        }])
    }

    func pickFile(_ url: URL) {
        guard isEmpty else { return }
        start([{
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > AttachmentLimits.maxBytes { throw CocoaError(.fileReadTooLarge) }
            guard ["pdf", "txt", "md", "csv", "docx", "xlsx"].contains(url.pathExtension.lowercased()) else {
                throw NSError(domain: "VeraBotAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: "支持 PDF、TXT、MD、CSV、DOCX 和 XLSX 文件"])
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= AttachmentLimits.maxBytes else { throw CocoaError(.fileReadTooLarge) }
            return Payload(data: data, mime: "application/octet-stream", filename: url.lastPathComponent)
        }])
    }

    private func start(_ loaders: [@MainActor () async throws -> Payload]) {
        self.loaders = loaders
        totalCount = loaders.count
        retry()
    }

    func retry() {
        guard !loaders.isEmpty, !isBusy, state != .sending else { return }
        state = .uploading
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for index in uploaded.count..<loaders.count {
                    let payload: Payload
                    if let cached = payloads[index] { payload = cached }
                    else {
                        payload = try await loaders[index]()
                        try Task.checkCancellation()
                        payloads[index] = payload
                    }
                    let result = try await api.uploadAttachment(data: payload.data, mime: payload.mime,
                                                               botID: botID, filename: payload.filename)
                    if Task.isCancelled {
                        _ = try? await api.deleteAttachment(id: result.id)
                        return
                    }
                    uploaded.append(result)
                    completedCount = uploaded.count
                    if !result.isFile { AttachmentImageStore.shared.put(result.id, data: payload.data) }
                    payloads[index] = nil
                }
                state = .ready(uploaded)
                task = nil
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(UserFacingError.message(for: error))
                task = nil
            }
        }
    }

    func remove() {
        task?.cancel()
        let ids = uploaded.map(\.id)
        let api = api
        Task { for id in ids { _ = try? await api.deleteAttachment(id: id) } }
        reset()
    }

    /// 先保留上传结果，直到调用方成功保存到持久发送队列。
    func beginSending() -> [Attachment] {
        let attachments = ready
        guard !attachments.isEmpty else { return [] }
        state = .sending
        return attachments
    }

    func finishSending(accepted: Bool) {
        if accepted { reset() }
        else { state = .failed("未能保存发送记录，请重试。") }
    }

    private func reset() {
        state = .empty
        loaders = []; payloads = [:]; uploaded = []
        completedCount = 0; totalCount = 0; task = nil
    }
}
