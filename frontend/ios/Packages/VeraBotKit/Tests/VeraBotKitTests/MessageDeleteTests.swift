import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

// 删除单条消息（MSG-DEL-K-01..03）：APIClient 请求形状与后端 DELETE /api/bots/{bot_id}/messages/{message_id} 一致。

/// 本地桩：记录收到的方法 + 路径；/messages/404 回 404，其余回 {"ok":true}
final class MessageDeleteStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var seen: [String] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "msgdel.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append("\(request.httpMethod ?? "") \(url.path)?\(url.query ?? "")") }
        let missing = url.path.hasSuffix("/messages/404")
        let body = Data((missing ? #"{"detail":"消息不存在"}"# : #"{"ok":true}"#).utf8)
        let resp = HTTPURLResponse(url: url, statusCode: missing ? 404 : 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func deleteStubClient() -> APIClient {
    let c = APITransport.makeConfiguration()
    c.protocolClasses = [MessageDeleteStub.self]
    return APIClient(baseURL: URL(string: "http://msgdel.test")!, token: "t", urlSession: URLSession(configuration: c))
}

@Test func deleteMessageSendsDeleteToMessagePath() async throws {
    let r = try await deleteStubClient().deleteMessage(botID: 42, messageID: 7)
    #expect(r.ok)
    let seen = MessageDeleteStub.lock.withLock { MessageDeleteStub.seen }
    #expect(seen.contains("DELETE /api/bots/42/messages/7?"))   // 无查询参数、不是清空整段对话的路径
}

@Test func deleteMessageSurfaces404() async {
    do {
        _ = try await deleteStubClient().deleteMessage(botID: 42, messageID: 404)
        Issue.record("expected 404")
    } catch let e as APIError {
        #expect(e.status == 404)
    } catch {
        Issue.record("unexpected \(error)")
    }
}

@Test func chatDoneDecodesUserMessageID() throws {
    // MSG-DEL-K-03：新后端带 user_message_id；旧后端不带时为 nil（向后兼容）
    let new = try JSONDecoder().decode(ChatDone.self, from: Data(#"{"message_id":9,"user_message_id":8,"usage":{},"memory_ids":[]}"#.utf8))
    #expect(new.messageID == 9 && new.userMessageID == 8)
    let old = try JSONDecoder().decode(ChatDone.self, from: Data(#"{"message_id":9}"#.utf8))
    #expect(old.messageID == 9 && old.userMessageID == nil && old.memoryIDs.isEmpty)
}
