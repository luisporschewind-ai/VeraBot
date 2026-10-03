import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

// 账号隔离 · HTTP 缓存（CACHE-K-01..07）：API 走无缓存的专用会话、退出 / 升级时清磁盘缓存、登录会话代号。

/// 本地桩：按路径计数，回一个「允许缓存一小时」的响应，看客户端会不会存下 / 复用它。
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hits: [String: Int] = [:]
    static let lock = NSLock()
    static func count(_ path: String) -> Int { lock.withLock { hits[path] ?? 0 } }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "stub.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.hits[url.path, default: 0] += 1 }
        let sse = url.path.hasSuffix("/chat")
        let body: Data
        if sse {
            body = Data("event: delta\ndata: {\"text\":\"你好\"}\n\nevent: done\ndata: {\"message_id\":7}\n\n".utf8)
        } else if url.path == "/api/me" {
            body = Data(#"{"id":1,"username":"u1","nickname":null,"has_avatar":false}"#.utf8)
        } else {
            body = Data(#"{"bots":[],"limit":20}"#.utf8)
        }
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": sse ? "text/event-stream" : "application/json",
            "Cache-Control": "public, max-age=3600",
        ])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .allowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let c = APITransport.makeConfiguration()
    c.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: c)
}

@Test func transportHasNoURLCache() {
    let c = APITransport.makeConfiguration()
    #expect(c.urlCache == nil)
    #expect(c.requestCachePolicy == .reloadIgnoringLocalCacheData)
    #expect(c.httpCookieStorage == nil && c.urlCredentialStorage == nil && !c.httpShouldSetCookies)
    #expect(APITransport.session !== URLSession.shared)
    #expect(APITransport.session.configuration.urlCache == nil)
    // 默认构造的客户端不用 URLSession.shared
    let session = AuthSession(tokens: nil)
    #expect(APIClient(baseURL: URL(string: "http://x")!, session: session).urlSession === APITransport.session)
    #expect(APIClient(baseURL: URL(string: "http://x")!, token: "t").urlSession === APITransport.session)
}

@Test func clientNeverServesOrStoresCachedResponses() async throws {
    let api = APIClient(baseURL: URL(string: "http://stub.test")!, token: "a", urlSession: stubSession())
    _ = try await api.me()
    _ = try await api.me()
    _ = try await api.bots()
    _ = try await api.bots()
    // 服务端允许缓存一小时，客户端仍然每次都走网络（没有 URLCache 可读 / 可写）
    #expect(StubProtocol.count("/api/me") == 2)
    #expect(StubProtocol.count("/api/bots") == 2)
}

@Test func sseUsesInjectedSession() async throws {
    let api = APIClient(baseURL: URL(string: "http://stub.test")!, token: "a", urlSession: stubSession())
    var text = ""
    var done = false
    for try await ev in api.chatStream(botID: 42, message: "hi") {
        if case .delta(let t) = ev { text += t }
        if case .done(let d) = ev { done = d.messageID == 7 }
    }
    #expect(text == "你好" && done)
    #expect(StubProtocol.count("/api/bots/42/chat") == 1)
}

@Test func purgeRemovesOnlyURLCacheFiles() throws {
    let fm = FileManager.default
    let caches = fm.temporaryDirectory.appendingPathComponent("vb-purge-\(UUID().uuidString)")
    let dir = caches.appendingPathComponent("com.verabot.app")
    try fm.createDirectory(at: dir.appendingPathComponent("fsCachedData"), withIntermediateDirectories: true)
    try fm.createDirectory(at: dir.appendingPathComponent("com.apple.metal"), withIntermediateDirectories: true)
    try fm.createDirectory(at: caches.appendingPathComponent("verabot-avatars"), withIntermediateDirectories: true)
    for name in ["Cache.db", "Cache.db-shm", "Cache.db-wal", "fsCachedData/ABC"] {
        try Data("secret".utf8).write(to: dir.appendingPathComponent(name))
    }
    let cache = URLCache(memoryCapacity: 1 << 20, diskCapacity: 0, directory: nil)
    let req = URLRequest(url: URL(string: "http://stub.test/api/me")!)
    cache.storeCachedResponse(CachedURLResponse(response: HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                                                data: Data("x".utf8)), for: req)
    #expect(cache.cachedResponse(for: req) != nil)

    let removed = HTTPCachePurge.purge(cachesDirectory: caches, bundleID: "com.verabot.app", sharedCache: cache)
    #expect(Set(removed.map(\.lastPathComponent)) == ["Cache.db", "Cache.db-shm", "Cache.db-wal", "fsCachedData"])
    #expect(cache.cachedResponse(for: req) == nil)
    for name in HTTPCachePurge.fileNames { #expect(!fm.fileExists(atPath: dir.appendingPathComponent(name).path)) }
    #expect(fm.fileExists(atPath: dir.appendingPathComponent("com.apple.metal").path))
    #expect(fm.fileExists(atPath: caches.appendingPathComponent("verabot-avatars").path))
    // 再清一次：没有可删的，不报错；空 bundle id 不动任何文件
    #expect(HTTPCachePurge.purge(cachesDirectory: caches, bundleID: "com.verabot.app", sharedCache: nil).isEmpty)
    #expect(HTTPCachePurge.purge(cachesDirectory: caches, bundleID: "", sharedCache: nil).isEmpty)
    try? fm.removeItem(at: caches)
}

@Test func purgeOnceAfterUpgrade() {
    let suite = "vb-purge-once-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    var runs = 0
    #expect(HTTPCachePurge.runOnce(defaults: d) { runs += 1 })
    #expect(!HTTPCachePurge.runOnce(defaults: d) { runs += 1 })
    #expect(runs == 1 && d.bool(forKey: HTTPCachePurge.purgedOnceKey))
    d.removePersistentDomain(forName: suite)
}

@Test func sessionGenerationChangesOnSignInAndOut() {
    let session = AuthSession(tokens: AuthTokens(access: "a", refresh: "r"))
    let g0 = session.generation
    #expect(session.isCurrent(g0))
    session.set(nil)                                              // 退出
    #expect(!session.isCurrent(g0))
    let g1 = session.generation
    #expect(!session.isCurrent(g1))                               // 未登录：任何代号都不算当前
    session.set(AuthTokens(access: "b", refresh: "r2"))           // 另一个账号登录
    let g2 = session.generation
    #expect(g2 != g0 && g2 != g1 && session.isCurrent(g2) && !session.isCurrent(g0))
}

@Test func staleRefreshDoesNotBumpOrOverrideNewSession() async {
    // A 的令牌被别的请求刷新过：复用不走网络，代号不变
    let session = AuthSession(tokens: AuthTokens(access: "new", refresh: "r"))
    let g = session.generation
    _ = await session.refresh(after: "old", baseURL: URL(string: "http://127.0.0.1:9")!)
    #expect(session.isCurrent(g))
}
