import Foundation
import VeraBotCore

public protocol TetrisSessionAPI: Sendable {
    func tetrisCapabilities() async throws -> TetrisCapabilities
    func currentTetrisSession() async throws -> TetrisRemoteSession?
    func createTetrisSession(_ request: TetrisHandoffRequest) async throws -> TetrisOperation
    func tetrisSession(id: String, afterVersion: Int64?, afterEventSequence: Int64?) async throws -> TetrisRemoteSession
    func tetrisOperation(requestID: String) async throws -> TetrisOperation
    func commandTetrisSession(id: String, request: TetrisCommandRequest) async throws -> TetrisOperation
}

// Explicit full signatures preserve protocol witness dispatch for the real client.
public extension TetrisSessionAPI {
    func tetrisCapabilities() async throws -> TetrisCapabilities { throw APIError(status: 501, message: "接管服务尚未开通") }
    func currentTetrisSession() async throws -> TetrisRemoteSession? { throw APIError(status: 501, message: "接管服务尚未开通") }
    func createTetrisSession(_ request: TetrisHandoffRequest) async throws -> TetrisOperation { throw APIError(status: 501, message: "接管服务尚未开通") }
    func tetrisSession(id: String, afterVersion: Int64?, afterEventSequence: Int64?) async throws -> TetrisRemoteSession { throw APIError(status: 501, message: "接管服务尚未开通") }
    func tetrisOperation(requestID: String) async throws -> TetrisOperation { throw APIError(status: 501, message: "接管服务尚未开通") }
    func commandTetrisSession(id: String, request: TetrisCommandRequest) async throws -> TetrisOperation { throw APIError(status: 501, message: "接管服务尚未开通") }
}

private struct CurrentTetrisResponse: Decodable { let session: TetrisRemoteSession? }
private let tetrisPath = "/api/games/tetris/sessions"
private func encodeTetris<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    guard data.count <= 65_536 else { throw TetrisSessionError.invalidContract }
    return data
}
private func validTetrisID(_ value: String) throws -> String {
    guard UUID(uuidString: value) != nil else { throw TetrisSessionError.invalidContract }
    return value
}
private func validateTetrisOperation(_ result: TetrisOperation, requestID: String) throws -> TetrisOperation {
    guard result.requestID == requestID else { throw TetrisSessionError.invalidContract }
    try result.session.validate()
    return result
}

extension APIClient {
    public func tetrisCapabilities() async throws -> TetrisCapabilities { try await call(tetrisPath + "/capabilities") }
    public func currentTetrisSession() async throws -> TetrisRemoteSession? {
        let result: CurrentTetrisResponse = try await call(tetrisPath + "/current")
        try result.session?.validate()
        return result.session
    }
    public func createTetrisSession(_ request: TetrisHandoffRequest) async throws -> TetrisOperation {
        _ = try validTetrisID(request.requestID); _ = try validTetrisID(request.clientID)
        let result: TetrisOperation = try await call(tetrisPath, method: "POST", body: encodeTetris(request))
        return try validateTetrisOperation(result, requestID: request.requestID)
    }
    public func tetrisSession(id: String, afterVersion: Int64?, afterEventSequence: Int64?) async throws -> TetrisRemoteSession {
        var query: [URLQueryItem] = []
        if let afterVersion { query.append(.init(name: "afterVersion", value: String(afterVersion))) }
        if let afterEventSequence { query.append(.init(name: "afterEventSequence", value: String(afterEventSequence))) }
        let result: TetrisRemoteSession = try await call(tetrisPath + "/" + validTetrisID(id), query: query)
        guard result.id == id else { throw TetrisSessionError.invalidContract }
        try result.validate()
        return result
    }
    public func tetrisOperation(requestID: String) async throws -> TetrisOperation {
        let result: TetrisOperation = try await call(tetrisPath + "/operations/" + validTetrisID(requestID))
        return try validateTetrisOperation(result, requestID: requestID)
    }
    public func commandTetrisSession(id: String, request: TetrisCommandRequest) async throws -> TetrisOperation {
        _ = try validTetrisID(request.requestID); _ = try validTetrisID(request.clientID)
        let result: TetrisOperation = try await call(tetrisPath + "/" + validTetrisID(id) + "/commands", method: "POST", body: encodeTetris(request))
        guard result.session.id == id else { throw TetrisSessionError.invalidContract }
        return try validateTetrisOperation(result, requestID: request.requestID)
    }
}
