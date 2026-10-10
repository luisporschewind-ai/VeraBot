import Foundation
import Testing
@testable import VeraBotNetworking

private final class AccountSwitchProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var auth: AuthSession?
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var switchDuringRefresh = false
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "account-switch.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let first = Self.lock.withLock { Self.requests += 1; return Self.requests == 1 }
        // 老账号请求到达服务端后，用户已在设备上切换账号；此时旧请求返回 401。
        let refreshing = request.url?.path == "/api/auth/refresh"
        if (first && !Self.switchDuringRefresh) || refreshing {
            Self.auth?.set(AuthTokens(access: "account-b", refresh: "refresh-b"))
        }
        let body = refreshing
            ? #"{"token":"refreshed-a","refresh_token":"refreshed-a-r","user":{"id":1,"username":"account-a"}}"#
            : (first ? #"{"detail":"旧会话已失效"}"# : #"{"id":2,"username":"account-b"}"#)
        let response = HTTPURLResponse(url: request.url!, statusCode: first ? 401 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func oldAccountRequestDoesNotRetryWithNewAccountToken() async throws {
    let config = APITransport.makeConfiguration()
    config.protocolClasses = [AccountSwitchProtocol.self]
    let transport = URLSession(configuration: config)
    defer { transport.invalidateAndCancel(); AccountSwitchProtocol.auth = nil }
    for duringRefresh in [false, true] {
        let auth = AuthSession(tokens: AuthTokens(access: "account-a", refresh: "refresh-a"), urlSession: transport)
        AccountSwitchProtocol.auth = auth
        AccountSwitchProtocol.requests = 0
        AccountSwitchProtocol.switchDuringRefresh = duringRefresh
        let api = APIClient(baseURL: URL(string: "http://account-switch.test")!, session: auth, urlSession: transport)
        do {
            _ = try await api.me()
            Issue.record("旧账号请求使用了新账号的令牌重试")
        } catch let error as APIError {
            #expect(error.status == 401)
        }
        #expect(AccountSwitchProtocol.requests == (duringRefresh ? 2 : 1))
        #expect(auth.accessToken == "account-b")
    }
}
