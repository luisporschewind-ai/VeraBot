import Foundation
import Testing
import VeraBotCore
@testable import VeraBotNetworking

private final class GroupTransportProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var auth: AuthSession?
    nonisolated(unsafe) static var scenario = ""
    nonisolated(unsafe) static var paths: [String] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    nonisolated(unsafe) static var authorizations: [String] = []
    static let lock = NSLock()
    static let snapshot = #"{"id":9,"group_id":7,"client_request_id":"11111111-1111-1111-1111-111111111111","mode":"single","status":"completed","cancel_requested":false,"messages":[]}"#
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "group-contract.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }; body.append(contentsOf: bytes.prefix(count))
            }
        }
        let path = request.url!.path
        let occurrence = Self.lock.withLock {
            Self.paths.append(path)
            if path.hasSuffix("/chat") { Self.bodies.append(body); Self.authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "") }
            return Self.paths.filter { $0 == path }.count
        }
        var status = 200
        var payload = #"{"groups":[]}"#
        if Self.scenario == "switch-success" {
            Self.auth?.set(AuthTokens(access: "b", refresh: "rb"))
        } else if path == "/api/auth/refresh" {
            if Self.scenario == "switch-refresh" { Self.auth?.set(nil) }
            payload = #"{"token":"fresh-a","refresh_token":"fresh-ra","user":{"id":1,"username":"a"}}"#
        } else if Self.scenario == "existing" && path.hasSuffix("/chat") {
            status = 409; payload = #"{"detail":{"code":"request_exists","message":"请求已存在","turn_id":9}}"#
        } else if path.hasSuffix("/turns/9") {
            payload = Self.snapshot
        } else if path.hasSuffix("/chat") && occurrence == 1 {
            status = 401; payload = #"{"detail":"expired"}"#
        } else if path.hasSuffix("/chat") {
            payload = "event: turn_done\ndata: {\"group_id\":7,\"turn_id\":9,\"status\":\"completed\",\"usage\":null,\"message_ids\":[]}\n\n"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": path.hasSuffix("/chat") && status == 200 ? "text/event-stream" : "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func GroupChatNetworkKeepsRequestsInTheirOriginalSession() async throws {
    let config = APITransport.makeConfiguration(); config.protocolClasses = [GroupTransportProtocol.self]
    let transport = URLSession(configuration: config)
    defer { transport.invalidateAndCancel(); GroupTransportProtocol.auth = nil }
    for scenario in ["switch-success", "switch-refresh", "refresh", "existing"] {
        let auth = AuthSession(tokens: AuthTokens(access: "a", refresh: "ra"), urlSession: transport)
        GroupTransportProtocol.auth = auth; GroupTransportProtocol.scenario = scenario
        GroupTransportProtocol.paths = []; GroupTransportProtocol.bodies = []; GroupTransportProtocol.authorizations = []
        let api = APIClient(baseURL: URL(string: "http://group-contract.test")!, session: auth, urlSession: transport)
        let request = GroupChatRequest(clientRequestID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, message: "讨论")
        do {
            if scenario == "switch-success" { _ = try await api.groups() }
            else {
                var events = 0
                for try await _ in api.groupChatStream(groupID: 7, request: request) { events += 1 }
                #expect(scenario == "refresh" && events == 1)
            }
            #expect(scenario == "refresh", "Old session or duplicate request must not produce success")
        } catch is CancellationError {
            #expect(scenario.hasPrefix("switch"))
        } catch let existing as GroupRequestExists {
            #expect(scenario == "existing" && existing.turn.id == 9)
        }
        if scenario == "refresh" {
            #expect(GroupTransportProtocol.authorizations == ["Bearer a", "Bearer fresh-a"])
            #expect(GroupTransportProtocol.bodies.count == 2)
            #expect(GroupTransportProtocol.bodies[0] == GroupTransportProtocol.bodies[1])
            let sent = try #require(JSONSerialization.jsonObject(with: GroupTransportProtocol.bodies[0]) as? [String: Any])
            #expect(sent["client_request_id"] as? String == request.clientRequestID.uuidString)
        } else if scenario == "existing" {
            #expect(GroupTransportProtocol.paths == ["/api/groups/7/chat", "/api/groups/7/turns/9"])
        } else if scenario == "switch-refresh" {
            #expect(GroupTransportProtocol.paths == ["/api/groups/7/chat", "/api/auth/refresh"])
        }
    }
}
