import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

private final class TetrisHTTPStub: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable { let method: String; let path: String; let query: String?; let body: Data }
    static let lock = NSLock()
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var seen: [Seen] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "tetris-session.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bytes = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while bytes.count <= 65536 { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count)) }
        }
        let handler = Self.lock.withLock {
            Self.seen.append(.init(method: request.httpMethod ?? "", path: request.url!.path, query: request.url?.query, body: bytes))
            return Self.handler
        }
        do {
            let (status, data) = try handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@Suite(.serialized) struct TetrisSessionAPITests {
    private let clientID = "00000000-0000-0000-0000-000000000001"
    private let sessionID = "00000000-0000-0000-0000-000000000002"
    private func value() -> TetrisRemoteSession {
        var game = TetrisGame(seed: 42, ruleVersion: "vera-tetris-2"); game.apply(.start)
        return .init(id: sessionID, originClientID: clientID, botID: 7, controller: .bot, runState: .running, version: 1, controlEpoch: 1, latestSnapshot: game.state, contribution: .init(playerScore: 0, playerLines: 0, botScore: 0, botLines: 0), updatedAt: 1)
    }
    private func api() -> (any VeraBotAPI, URLSession) {
        TetrisHTTPStub.lock.withLock { TetrisHTTPStub.seen = [] }
        let config = APITransport.makeConfiguration(); config.protocolClasses = [TetrisHTTPStub.self]
        let session = URLSession(configuration: config)
        return (APIClient(baseURL: URL(string: "https://tetris-session.test")!, token: "test", urlSession: session), session)
    }
    @Test func actualProtocolDispatchAndStableRequestID() async throws {
        let (api, session) = api(); defer { session.invalidateAndCancel() }
        let request = TetrisHandoffRequest(clientID: clientID, botID: 7, snapshot: value().latestSnapshot)
        let response = try JSONEncoder().encode(TetrisOperation(requestID: request.requestID, status: .committed, session: value()))
        TetrisHTTPStub.lock.withLock { TetrisHTTPStub.handler = { _ in (200, response) } }
        _ = try await api.createTetrisSession(request); _ = try await api.createTetrisSession(request)
        _ = try await api.tetrisOperation(requestID: request.requestID)
        let seen = TetrisHTTPStub.lock.withLock { TetrisHTTPStub.seen }
        #expect(seen.map(\.method) == ["POST", "POST", "GET"])
        #expect(seen[0].path == "/api/games/tetris/sessions")
        #expect(seen[2].path == "/api/games/tetris/sessions/operations/\(request.requestID)")
        #expect(seen[0].body == seen[1].body)
        let body = try JSONSerialization.jsonObject(with: seen[0].body) as! [String: Any]
        #expect(body["expectedEpoch"] as? Int == 0)
        #expect(body["requestID"] as? String == request.requestID)
    }
    @Test func queryAndCommandPaths() async throws {
        let (api, session) = api(); defer { session.invalidateAndCancel() }
        let remote = try JSONEncoder().encode(value())
        TetrisHTTPStub.lock.withLock { TetrisHTTPStub.handler = { _ in (200, remote) } }
        _ = try await api.tetrisSession(id: sessionID, afterVersion: 1, afterEventSequence: 3)
        let command = TetrisCommandRequest(clientID: clientID, expectedVersion: 1, expectedEpoch: 1, command: .reclaim)
        let response = try JSONEncoder().encode(TetrisOperation(requestID: command.requestID, status: .pending, session: value()))
        TetrisHTTPStub.lock.withLock { TetrisHTTPStub.handler = { _ in (200, response) } }
        _ = try await api.commandTetrisSession(id: sessionID, request: command)
        let seen = TetrisHTTPStub.lock.withLock { TetrisHTTPStub.seen }
        #expect(seen[0].query?.contains("afterVersion=1") == true)
        #expect(seen[0].query?.contains("afterEventSequence=3") == true)
        #expect(seen[1].method == "POST" && seen[1].path == "/api/games/tetris/sessions/\(sessionID)/commands")
    }
    @Test func errorsRemainDistinguishable() async throws {
        let (api, session) = api(); defer { session.invalidateAndCancel() }
        for status in [403,409,422,503] {
            TetrisHTTPStub.lock.withLock { TetrisHTTPStub.handler = { _ in (status, Data(#"{"detail":"test"}"#.utf8)) } }
            do { _ = try await api.tetrisSession(id: sessionID, afterVersion: nil, afterEventSequence: nil); Issue.record("error expected") }
            catch let error as APIError { #expect(error.status == status) }
        }
    }
    @Test func unsupportedRulesAndInvalidPathsAreRejected() async throws {
        let (api, session) = api(); defer { session.invalidateAndCancel() }
        var invalid = value(); invalid.latestSnapshot.ruleVersion = "future-version"
        let data = try JSONEncoder().encode(invalid)
        TetrisHTTPStub.lock.withLock { TetrisHTTPStub.handler = { _ in (200, data) } }
        do { _ = try await api.tetrisSession(id: sessionID, afterVersion: nil, afterEventSequence: nil); Issue.record("rule rejection expected") } catch {}
        let before = TetrisHTTPStub.lock.withLock { TetrisHTTPStub.seen.count }
        do { _ = try await api.tetrisSession(id: "../other", afterVersion: nil, afterEventSequence: nil); Issue.record("path rejection expected") } catch {}
        #expect(TetrisHTTPStub.lock.withLock { TetrisHTTPStub.seen.count } == before)
    }
}
