import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

// MEM-UI-13：消息反馈（记忆 M2）与后端 `POST/DELETE /api/messages/{id}/feedback` 一一对应。

/// 本地桩：记录方法 + 路径 + 请求体；POST 回带 style 提议的评价结果，DELETE 回 {"ok":true}
final class FeedbackStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var seen: [String] = []
    /// 按「METHOD 路径」记请求体：测试并行执行，不能只看最后一条
    nonisolated(unsafe) static var bodies: [String: String] = [:]
    static let lock = NSLock()

    static let reply = ##"""
    {"ok":true,"message_id":7,"rating":-1,"reason":"too_long",
     "proposal":{"memory_id":31,"status":"proposed","action":"create","content":"回答更简短，直接说重点",
                 "type":"style","scope":"bot","sensitivity":"normal","sensitive":false,"expires_at":null}}
    """##

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "feedback.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        // URLProtocol 看不到 httpBody 流，从 httpBodyStream 读（APIClient 走 upload/stream 时为流）
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            body = data
        }
        Self.lock.withLock {
            let key = "\(request.httpMethod ?? "") \(url.path)"
            Self.seen.append(key)
            Self.bodies[key] = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        let isPost = request.httpMethod == "POST"
        let json = isPost ? Self.reply : #"{"ok":true,"deleted":1}"#
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func feedbackStubClient() -> APIClient {
    let c = APITransport.makeConfiguration()
    c.protocolClasses = [FeedbackStub.self]
    return APIClient(baseURL: URL(string: "http://feedback.test")!, token: "t", urlSession: URLSession(configuration: c))
}

@Test func feedbackPostsRatingAndReason() async throws {
    let r = try await feedbackStubClient().setFeedback(messageID: 7, rating: -1, reason: .tooLong)
    #expect(r.rating == -1 && r.reason == .tooLong)
    let body = FeedbackStub.lock.withLock { FeedbackStub.bodies["POST /api/messages/7/feedback"] ?? "" }
    #expect(body.contains(#""reason":"too_long""#))
}

@Test func feedbackThumbsUpOmitsReason() async throws {
    _ = try await feedbackStubClient().setFeedback(messageID: 9, rating: 1, reason: nil)
    let body = FeedbackStub.lock.withLock { FeedbackStub.bodies["POST /api/messages/9/feedback"] ?? "" }
    #expect(body.contains(#""rating":1"#))
    #expect(!body.contains("reason"))   // 👍 不带理由（后端也会把 reason 归零）
}

@Test func clearFeedbackDeletesSamePath() async throws {
    _ = try await feedbackStubClient().clearFeedback(messageID: 11)
    let seen = FeedbackStub.lock.withLock { FeedbackStub.seen }
    #expect(seen.contains("DELETE /api/messages/11/feedback"))
}

@Test func proposalInResponseBecomesCard() async throws {
    let r = try await feedbackStubClient().setFeedback(messageID: 7, rating: -1, reason: .tooLong)
    let trace = try #require(r.proposalTrace)
    let p = try #require(trace.memoryProposal)
    #expect(p.isCard)                       // 有 memory_id 且 status == proposed → 渲染确认卡片
    #expect(p.memoryID == 31)
    #expect(p.type == .style && p.scope == .bot)
    #expect(p.content == "回答更简短，直接说重点")
}

@Test func noProposalMeansNoCard() throws {
    let json = ##"{"ok":true,"message_id":7,"rating":1,"reason":null,"proposal":null}"##
    let r = try JSONDecoder().decode(FeedbackResponse.self, from: Data(json.utf8))
    #expect(r.proposalTrace == nil)
}

@Test func messageDecodesFeedback() throws {
    let withFeedback = ##"""
    {"id":7,"role":"assistant","content":"好的",
     "feedback":{"rating":-1,"reason":"tone","created_at":"2026-10-05T01:00:00+00:00"}}
    """##
    let m = try JSONDecoder().decode(ChatMessage.self, from: Data(withFeedback.utf8))
    #expect(m.feedback?.rating == -1 && m.feedback?.reason == .tone)

    // 没评过 / 旧后端：键不存在 → nil
    let plain = try JSONDecoder().decode(ChatMessage.self, from: Data(#"{"id":8,"role":"assistant","content":"好的"}"#.utf8))
    #expect(plain.feedback == nil && plain.attachments.isEmpty)
}
