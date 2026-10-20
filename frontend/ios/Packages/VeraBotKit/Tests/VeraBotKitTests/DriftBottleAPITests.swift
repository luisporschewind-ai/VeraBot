import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

private final class DriftHTTPStub: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable { let method: String; let path: String; let query: String?; let body: Data }
    static let lock = NSLock()
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var seen: [Seen] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "drift-bottle.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bytes = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while bytes.count <= 65_536 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
        }
        let handler = Self.lock.withLock {
            Self.seen.append(.init(method: request.httpMethod ?? "", path: request.url!.path,
                                   query: request.url?.query, body: bytes))
            return Self.handler
        }
        do {
            let (status, data) = try handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private let stateJSON = """
{"server_time":100,"current":null,"limits":{"max_contributions_per_bottle":50,"hold_seconds":86400,"public_length_min":1,"public_length_max":1000,"opening_max_length":120,"chat_max_length":300,"publish_per_minute":5,"draw_per_minute":10,"generate_per_minute":10},"has_active_encounter":false}
"""

private let emptyDrawJSON = """
{"operation":{"request_id":"request-draw-1","status":"committed","kind":"draw","error_code":null,"error_message":null,"retryable":false},"encounter":null}
"""

private let releaseJSON = """
{"operation":{"request_id":"request-release-1","status":"committed","kind":"release","error_code":null,"error_message":null,"retryable":false},"record":{"id":"encounter:1","kind":"encounter","title":"和 小满 一起读了一封信","subtitle":"一封信","created_at":100,"completed_at":200,"encounter":{"id":1,"bottle_id":2,"bot_id":7,"bot_name":"小满","bot_avatar":"🌊","bot_color":"#0F766E","bot_deleted":false,"started_at":100,"expires_at":86500,"ended_at":200,"end_reason":"returned","version":2,"bottle_version":3,"lease_token":"lease-token","read_limit":1,"quiet":false,"remaining_seconds":0,"is_expired":false,"can_publish":false,"contributions":[],"next_cursor":null,"turns":[],"memory":null},"release":null,"contributions":[],"turns":[],"memory":null}}
"""

@Suite(.serialized) struct DriftBottleAPITests {
    private func api() -> (any VeraBotAPI, URLSession) {
        DriftHTTPStub.lock.withLock {
            DriftHTTPStub.seen = []
            DriftHTTPStub.handler = { request in
                if request.url!.path.hasSuffix("/state") { return (200, Data(stateJSON.utf8)) }
                if request.url!.path.hasSuffix("/encounters") { return (200, Data(emptyDrawJSON.utf8)) }
                if request.url!.path.contains("/release") { return (200, Data(releaseJSON.utf8)) }
                if request.httpMethod == "GET", request.url!.path.contains("/records/") {
                    return (200, Data("""
                    {"id":"encounter:1","kind":"encounter","title":"和 小满 一起读了一封信","subtitle":"一封信","created_at":100,"completed_at":200,"encounter":null,"release":null,"contributions":[],"turns":[],"memory":null}
                    """.utf8))
                }
                if request.httpMethod == "DELETE" {
                    return (200, Data("""
                    {"operation":{"request_id":"request-delete-1","status":"committed","kind":"delete_record","error_code":null,"error_message":null,"retryable":false},"deleted":true}
                    """.utf8))
                }
                if request.url!.path.contains("/operations/") {
                    return (200, Data("""
                    {"operation":{"request_id":"request-release-1","status":"committed","kind":"release","error_code":null,"error_message":null,"retryable":false},"result":null}
                    """.utf8))
                }
                return (200, Data("""
                {"operation":{"request_id":"request-patch-1","status":"committed","kind":"patch_memory","error_code":null,"error_message":null,"retryable":false},"memory":{"id":1,"encounter_id":1,"record_id":"encounter:1","title":"标题","summary":"摘要","owner_note":"","edited":false,"generated_by":"bot","source_turn_ids":[],"version":1,"created_at":100,"updated_at":100}}
                """.utf8))
            }
        }
        let config = APITransport.makeConfiguration()
        config.protocolClasses = [DriftHTTPStub.self]
        let session = URLSession(configuration: config)
        return (APIClient(baseURL: URL(string: "https://drift-bottle.test")!, token: "test",
                          urlSession: session), session)
    }

    @Test func stateDrawReleasePathsAndStableRequestIDs() async throws {
        let (api, session) = api(); defer { session.invalidateAndCancel() }
        let state = try await api.driftBottleState()
        #expect(state.current == nil)
        #expect(state.limits.maxContributionsPerBottle == 50)

        let draw = DriftBottleDrawRequest(requestID: "request-draw-1", botID: 7)
        let empty = try await api.drawDriftBottle(draw)
        #expect(empty.encounter == nil)

        let release = DriftBottleReleaseRequest(
            requestID: "request-release-1", leaseToken: "lease-token", expectedVersion: 3,
            contribution: .init(body: "我也看见那片海了。", authorship: .owner))
        _ = try await api.releaseDriftBottle(encounterID: 1, request: release)
        _ = try await api.releaseDriftBottle(encounterID: 1, request: release)

        let seen = DriftHTTPStub.lock.withLock { DriftHTTPStub.seen }
        #expect(seen.map(\.method) == ["GET", "POST", "POST", "POST"])
        #expect(seen[0].path == "/api/games/drift-bottle/state")
        #expect(seen[1].path == "/api/games/drift-bottle/encounters")
        #expect(seen[2].path == "/api/games/drift-bottle/encounters/1/release")
        #expect(try JSONSerialization.jsonObject(with: seen[2].body) as? NSDictionary
                == (try JSONSerialization.jsonObject(with: seen[3].body) as? NSDictionary))
        let body = try JSONSerialization.jsonObject(with: seen[2].body) as! [String: Any]
        #expect(body["request_id"] as? String == "request-release-1")
        #expect((body["contribution"] as? [String: Any])?["body"] as? String == "我也看见那片海了。")
    }

    @Test func recordMemoryAndOperationPathsCarryRequestIDs() async throws {
        let (api, session) = api(); defer { session.invalidateAndCancel() }
        _ = try await api.driftBottleRecord(id: "encounter:1")
        _ = try await api.patchDriftBottleMemory(
            recordID: "encounter:1", requestID: "request-patch-1",
            patch: .init(title: "标题", expectedVersion: 1))
        _ = try await api.deleteDriftBottleRecord(id: "encounter:1", requestID: "request-delete-1")
        _ = try await api.driftBottleOperation(requestID: "request-release-1")
        let seen = DriftHTTPStub.lock.withLock { DriftHTTPStub.seen }
        #expect(seen[0].path == "/api/games/drift-bottle/records/encounter:1")
        #expect(seen[1].method == "PATCH")
        #expect(seen[1].path == "/api/games/drift-bottle/records/encounter:1/memory")
        #expect(seen[1].query?.contains("request_id=request-patch-1") == true)
        #expect(seen[2].method == "DELETE")
        #expect(seen[2].query?.contains("request_id=request-delete-1") == true)
        #expect(seen[3].path == "/api/games/drift-bottle/operations/request-release-1")
    }

    @Test func serverErrorsStayDistinguishable() async throws {
        let (api, session) = api(); defer { session.invalidateAndCancel() }
        DriftHTTPStub.lock.withLock {
            DriftHTTPStub.handler = { _ in (409, Data(#"{"detail":{"message":"这次相遇已到期","code":"encounter_expired"}}"#.utf8)) }
        }
        do {
            _ = try await api.driftBottleState()
            Issue.record("error expected")
        } catch let error as APIError {
            #expect(error.status == 409)
            #expect(error.code == "encounter_expired")
            #expect(error.message == "这次相遇已到期")
        }
    }
}
