// API 网络传输与 HTTP 缓存清理（账号隔离）。
//
// 背景：之前所有请求走 `URLSession.shared`（默认 URLCache），登录 / 刷新响应里的令牌、聊天记录、
// 已解密的健康记忆都被明文写进 `Library/Caches/<bundle id>/Cache.db`，退出登录、换账号后仍在。
// 现在：API（含 SSE、上传、头像下载、刷新令牌）统一走 `APITransport.session`（ephemeral、无 URLCache）；
// 退出 / 换账号、以及升级后首次启动时用 `HTTPCachePurge` 清掉旧的磁盘缓存。后端同时给 /api/* 加了
// `Cache-Control: no-store`（见 backend/verabot/core/http_cache.py）。
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum APITransport {
    /// 专用配置：ephemeral（cookie / 凭据 / 缓存都不落盘），并且完全不带 URLCache、不读本地缓存。
    public static func makeConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        return c
    }

    /// App 内所有 API 请求共用的会话（不是 `URLSession.shared`）。
    public static let session = URLSession(configuration: makeConfiguration())
}

public enum HTTPCachePurge {
    /// URLCache 在 `Caches/<bundle id>/` 下写的文件 / 目录（Metal 着色器缓存等其他内容不动）。
    public static let fileNames = ["Cache.db", "Cache.db-shm", "Cache.db-wal", "fsCachedData"]

    /// 升级后首次启动清一次用的标记（v1 = 本次修复）。
    public static let purgedOnceKey = "vb_http_cache_purged_v1"

    /// 清空 `sharedCache`（内存 + 磁盘记录），再删掉磁盘上的缓存文件。返回实际删掉的路径。
    @discardableResult
    public static func purge(cachesDirectory: URL, bundleID: String, sharedCache: URLCache? = URLCache.shared,
                             fileManager: FileManager = .default) -> [URL] {
        sharedCache?.removeAllCachedResponses()
        guard !bundleID.isEmpty else { return [] }
        let dir = cachesDirectory.appendingPathComponent(bundleID, isDirectory: true)
        var removed: [URL] = []
        for name in fileNames {
            let url = dir.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try? fileManager.removeItem(at: url)
            if !fileManager.fileExists(atPath: url.path) { removed.append(url) }
        }
        return removed
    }

    /// 当前 App 的 Caches 目录 + bundle id。
    @discardableResult
    public static func purgeAppCaches() -> [URL] {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return [] }
        return purge(cachesDirectory: caches, bundleID: Bundle.main.bundleIdentifier ?? "")
    }

    /// 只在第一次调用时执行 `action`（写标记到 defaults），返回这次是否执行了。
    @discardableResult
    public static func runOnce(defaults: UserDefaults, key: String = purgedOnceKey, _ action: () -> Void) -> Bool {
        if defaults.bool(forKey: key) { return false }
        action()
        defaults.set(true, forKey: key)
        return true
    }
}
