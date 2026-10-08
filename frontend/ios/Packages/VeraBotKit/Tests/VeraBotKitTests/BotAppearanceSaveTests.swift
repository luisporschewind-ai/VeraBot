import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

private final class AppearanceReceiptStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".appearance.test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.host == "network.appearance.test" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            var result = Data()
            while stream.hasBytesAvailable {
                let n = stream.read(&bytes, maxLength: bytes.count)
                if n <= 0 { break }
                result.append(contentsOf: bytes.prefix(n))
            }
            data = result
        }
        let payload = try? JSONDecoder().decode(JSONValue.self, from: data ?? Data())
        var response: [String: JSONValue] = ["id": .number(7), "name": .string("Vera"), "avatar": .string("veraBean"), "color": .string("#0F766E")]
        let valid = request.httpMethod == "PATCH" && url.path == "/api/bots/7"
            && { if case .object(let fields) = payload { return Set(fields.keys) == ["appearance"] }; return false }()
        response["appearance"] = payload?["appearance"] ?? .null
        if url.host == "old.appearance.test" { response.removeValue(forKey: "appearance") }
        if url.host == "mismatch.appearance.test" { response["appearance"] = .null }
        if url.host == "wrong-id.appearance.test" { response["id"] = .number(8) }
        let body = try! JSONEncoder().encode(JSONValue.object(response))
        let http = HTTPURLResponse(url: url, statusCode: valid ? 200 : 422, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func appearanceService(_ mode: String) -> BotAppearanceSaveService {
    let config = APITransport.makeConfiguration()
    config.protocolClasses = [AppearanceReceiptStub.self]
    return BotAppearanceSaveService(api: APIClient(baseURL: URL(string: "http://\(mode).appearance.test")!, token: "test", urlSession: URLSession(configuration: config)))
}

@Test func appearanceSaveOnlyPatchesAppearanceAndVerifiesEcho() async throws {
    let bot = try await appearanceService("good").save(botID: 7, appearance: .robotDefault)
    #expect(bot.id == 7 && bot.supportedAppearance == .robotDefault)
    #expect(bot.avatar == "veraBean" && bot.color == "#0F766E")
    let clear = try await appearanceService("good").save(botID: 7, appearance: nil)
    #expect(clear.appearanceFieldPresent && clear.appearance == nil)
}
@Test func appearanceSaveRejectsMissingMismatchedOrWrongTargetReceipt() async {
    for mode in ["old", "mismatch", "wrong-id"] {
        await #expect(throws: BotAppearanceSaveError.self) {
            try await appearanceService(mode).save(botID: 7, appearance: .robotDefault)
        }
    }
    await #expect(throws: BotAppearanceSaveError.self) {
        try await appearanceService("old").save(botID: 7, appearance: nil)
    }
}
@Test func appearanceNetworkFailureKeepsDraft() async throws {
    var draft = BotAppearanceDraft(saved: .robotDefault)
    var changed = draft.current
    changed.parameters.roundness = 0.8
    try draft.update(changed)
    await #expect(throws: (any Error).self) { try await appearanceService("network").save(botID: 7, appearance: changed) }
    #expect(draft.current == changed && draft.isDirty)
}

@Test func appearanceLocalAtomicRoundTripAndCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = BotAppearanceFileStore(directory: directory)
    #expect(try store.load() == nil)
    try store.save(.robotDefault)
    #expect(try store.load() == .robotDefault)
    let file = directory.appendingPathComponent("appearance-v1.json")
    let corrupt = Data("{future-or-corrupt}".utf8)
    try corrupt.write(to: file)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try Data(contentsOf: file) == corrupt)
    var invalid = BotAppearance.robotDefault
    invalid.parameters.roundness = -1
    #expect(throws: (any Error).self) { try store.save(invalid) }
    #expect(try Data(contentsOf: file) == corrupt)
}
