import Foundation
import VeraBotCore
import VeraBotNetworking

/// 对话图片的内存缓存（只在内存，不落盘；服务器响应是 no-store）。
/// 按会话代号隔离：退出 / 换账号时 `clearAll()`，之前发出的下载回来后发现代号变了就丢掉。
@MainActor
final class AttachmentImageStore {
    static let shared = AttachmentImageStore()

    private let cache = NSCache<NSString, NSData>()
    private var epoch = 0

    init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func cached(_ id: String) -> Data? {
        cache.object(forKey: id as NSString) as Data?
    }

    func put(_ id: String, data: Data) {
        cache.setObject(data as NSData, forKey: id as NSString, cost: data.count)
    }

    /// 原图字节：先查内存，再走鉴权下载。
    func load(_ id: String, api: any VeraBotAPI) async throws -> Data {
        if let data = cached(id) { return data }
        let started = epoch
        let data = try await api.attachmentContent(id: id)
        guard started == epoch else { throw CancellationError() }
        put(id, data: data)
        return data
    }

    func clearAll() {
        cache.removeAllObjects()
        epoch += 1
        AttachmentPreviewFiles.removeAll()
    }
}

/// 全屏查看（Quick Look）需要文件 URL：临时写到 tmp/vb-attachment-preview，关闭预览或退出登录时删除。
/// 写入的是原图字节（不重新编码）；扩展名按文件头取（GIF → .gif），Quick Look 按扩展名识别类型，GIF 才会播放动画。
enum AttachmentPreviewFiles {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vb-attachment-preview", isDirectory: true)
    }

    static func write(_ data: Data, id: String, ext: String? = nil) -> URL? {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(id).appendingPathExtension(ext ?? AttachmentLimits.fileExtension(for: data))
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
