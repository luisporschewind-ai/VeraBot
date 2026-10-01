import UIKit
import VeraBotCore
import VeraBotNetworking

/// 头像内存缓存（Avatar cache）。首页、设置、对话、Bot 列表读同一份，避免各页面各自请求。
/// 用户头像另存一份 JPEG 到 Caches，冷启动时先显示，再由 AppState.refreshProfile 按服务端时间戳对齐。
@MainActor
@Observable
final class AvatarStore {
    private(set) var userImage: UIImage?
    private(set) var botImages: [Int: UIImage] = [:]
    private var botStamp: [Int: String] = [:]
    private var clearedBots: Set<Int> = []
    private var userStamp: String?
    private var inflight: Set<Int> = []

    func image(forBot id: Int) -> UIImage? {
        if clearedBots.contains(id) { return nil }
        return botImages[id]
    }

    func noteUserStamp(_ updatedAt: String?) {
        userStamp = updatedAt
    }

    func loadCachedUser() {
        guard let data = read("user.jpg"), let image = UIImage(data: data) else { return }
        userImage = image
    }

    func setUser(image: UIImage?, updatedAt: String?) {
        userImage = image
        userStamp = updatedAt
        if let image, let data = image.jpegData(compressionQuality: 0.85) {
            write(data, name: "user.jpg")
        } else {
            removeFile("user.jpg")
        }
    }

    func setBot(id: Int, image: UIImage?, updatedAt: String?) {
        if let image {
            clearedBots.remove(id)
            var next = botImages
            next[id] = image
            botImages = next
            if let updatedAt { botStamp[id] = updatedAt } else { botStamp.removeValue(forKey: id) }
            if let data = image.jpegData(compressionQuality: 0.85) {
                write(data, name: "bot-\(id).jpg")
            }
        } else {
            clearedBots.insert(id)
            var next = botImages
            next.removeValue(forKey: id)
            botImages = next
            botStamp.removeValue(forKey: id)
            removeFile("bot-\(id).jpg")
        }
    }

    /// 列表从服务端刷新后对齐：没头像就清掉；时间戳变了就允许重新下载。
    func reconcileBot(id: Int, hasAvatar: Bool, updatedAt: String?) {
        if !hasAvatar {
            setBot(id: id, image: nil, updatedAt: nil)
            return
        }
        clearedBots.remove(id)
        if botStamp[id] != updatedAt {
            botStamp.removeValue(forKey: id)
        }
    }

    func clearAll() {
        userImage = nil
        userStamp = nil
        botImages = [:]
        botStamp = [:]
        clearedBots = []
        inflight = []
        if let dir = try? directory() {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func needsUserDownload(updatedAt: String?) -> Bool {
        userImage == nil || userStamp != updatedAt
    }

    func ensureBot(id: Int, hasAvatar: Bool, updatedAt: String?, api: any VeraBotAPI) async {
        if clearedBots.contains(id) || !hasAvatar { return }
        if botImages[id] == nil, let data = read("bot-\(id).jpg"), let image = UIImage(data: data) {
            var next = botImages
            next[id] = image
            botImages = next
        }
        if botImages[id] != nil, botStamp[id] == updatedAt, updatedAt != nil { return }
        if inflight.contains(id) { return }
        inflight.insert(id)
        defer { inflight.remove(id) }
        do {
            let data = try await api.botAvatarData(botID: id)
            guard !clearedBots.contains(id), let image = UIImage(data: data) else { return }
            setBot(id: id, image: image, updatedAt: updatedAt)
        } catch {
            // 下载失败时保留表情或已有缓存
        }
    }

    // MARK: - Disk

    private func directory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("verabot-avatars", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func fileURL(_ name: String) -> URL? {
        try? directory().appendingPathComponent(name)
    }

    private func read(_ name: String) -> Data? {
        guard let url = fileURL(name) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func write(_ data: Data, name: String) {
        guard let url = fileURL(name) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func removeFile(_ name: String) {
        guard let url = fileURL(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
