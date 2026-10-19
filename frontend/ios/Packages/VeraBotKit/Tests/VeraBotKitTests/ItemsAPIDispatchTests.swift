import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

/// 回归：`any VeraBotAPI` 上省略参数的 `items()` 必须走到 APIClient，而不是扩展里的 501 占位。
final class ItemsAPIDispatchStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var seen: [String] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "items-dispatch.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock {
            Self.seen.append("\(request.httpMethod ?? "") \(url.path)")
        }
        let body = Data(#"{"items":[],"server_time":"2026-10-19T00:00:00Z"}"#.utf8)
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test func existentialItemsOmittingArgsHitsAPIClientNot501Placeholder() async throws {
    ItemsAPIDispatchStub.lock.withLock { ItemsAPIDispatchStub.seen = [] }
    let config = APITransport.makeConfiguration()
    config.protocolClasses = [ItemsAPIDispatchStub.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let client = APIClient(baseURL: URL(string: "http://items-dispatch.test")!, token: "t", urlSession: session)
    let api: any VeraBotAPI = client
    let response = try await api.items()
    #expect(response.items.isEmpty)
    let seen = ItemsAPIDispatchStub.lock.withLock { ItemsAPIDispatchStub.seen }
    #expect(seen.contains("GET /api/items"))
}
