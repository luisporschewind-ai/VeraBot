import Foundation
import Testing
@testable import VeraBotNetworking

private final class LibraryContentProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "library-content.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer access"
        let path = request.url!.path
        let status = authorized && path == "/api/library/items/retained/thumb" ? 200 : 410
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((status == 200 ? "image-bytes" : "{\"detail\":\"missing\"}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func libraryPreviewUsesIndependentAuthorizedEndpointAndReportsMissingResources() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [LibraryContentProtocol.self]
    let transport = URLSession(configuration: config)
    defer { transport.invalidateAndCancel() }
    let api = APIClient(baseURL: URL(string:"http://library-content.test")!, token:"access", urlSession:transport)
    #expect(try await api.libraryThumbnail(id:"retained") == Data("image-bytes".utf8))
    do {
        _ = try await api.libraryThumbnail(id:"deleted")
        Issue.record("A missing preview must not become image data")
    } catch let error as APIError { #expect(error.status == 410) }
}
