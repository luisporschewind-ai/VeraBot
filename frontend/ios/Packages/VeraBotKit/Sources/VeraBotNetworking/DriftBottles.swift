import Foundation
import VeraBotCore

/// Drift Bottle transport. Implemented by `APIClient`; tests use the same
/// protocol to inject a deterministic fake.
public protocol DriftBottleAPI: Sendable {
    func driftBottleState() async throws -> DriftBottleState
    func createDriftBottle(_ request: DriftBottleCreateRequest) async throws -> DriftBottleCreateResponse
    func drawDriftBottle(_ request: DriftBottleDrawRequest) async throws -> DriftBottleDrawResponse
    func driftBottleEncounter(id: Int, cursor: String?) async throws -> DriftBottleEncounter
    func sendDriftBottleTurn(encounterID: Int, request: DriftBottleTurnRequest) async throws -> DriftBottleTurnResponse
    func releaseDriftBottle(encounterID: Int, request: DriftBottleReleaseRequest) async throws -> DriftBottleReleaseResponse
    func generateDriftBottleMemory(encounterID: Int, request: DriftBottleMemoryRequest) async throws -> DriftBottleMemoryResponse
    func driftBottleDraftSuggestion(_ request: DriftBottleDraftSuggestionRequest) async throws -> DriftBottleDraftSuggestionResponse
    func driftBottleRecords(botID: Int?, cursor: String?, limit: Int) async throws -> DriftBottleRecordsResponse
    func driftBottleRecord(id: String) async throws -> DriftBottleRecord
    func patchDriftBottleMemory(recordID: String, requestID: String,
                                patch: DriftBottleMemoryPatch) async throws -> DriftBottleMemoryResponse
    func deleteDriftBottleMemory(recordID: String, requestID: String) async throws -> DriftBottleDeleteResponse
    func deleteDriftBottleRecord(id: String, requestID: String) async throws -> DriftBottleDeleteResponse
    func withdrawDriftBottleContribution(id: Int,
                                         request: DriftBottleWithdrawRequest) async throws -> DriftBottleWithdrawResponse
    func reportDriftBottleContribution(_ request: DriftBottleReportRequest) async throws -> DriftBottleReportResponse
    func blockDriftBottleContributor(_ request: DriftBottleBlockRequest) async throws -> DriftBottleBlockResponse
    func driftBottleOperation(requestID: String) async throws -> DriftBottleOperationEnvelope
}

private let driftBottlePath = "/api/games/drift-bottle"

extension APIClient {
    public func driftBottleState() async throws -> DriftBottleState {
        try await call(driftBottlePath + "/state")
    }

    public func createDriftBottle(_ request: DriftBottleCreateRequest) async throws -> DriftBottleCreateResponse {
        let response: DriftBottleCreateResponse = try await call(driftBottlePath + "/bottles",
                                                                 method: "POST", body: try encode(request))
        guard response.operation.requestID == request.requestID else {
            throw APIError(status: 502, message: "服务器返回了不一致的请求编号")
        }
        return response
    }

    public func drawDriftBottle(_ request: DriftBottleDrawRequest) async throws -> DriftBottleDrawResponse {
        let response: DriftBottleDrawResponse = try await call(driftBottlePath + "/encounters",
                                                               method: "POST", body: try encode(request))
        guard response.operation.requestID == request.requestID else {
            throw APIError(status: 502, message: "服务器返回了不一致的请求编号")
        }
        return response
    }

    public func driftBottleEncounter(id: Int, cursor: String?) async throws -> DriftBottleEncounter {
        var query: [URLQueryItem] = []
        if let cursor, !cursor.isEmpty { query.append(.init(name: "cursor", value: cursor)) }
        let response: DriftBottleEncounter = try await call("\(driftBottlePath)/encounters/\(id)", query: query)
        guard response.id == id else { throw APIError(status: 502, message: "服务器返回了另一段相遇") }
        return response
    }

    public func sendDriftBottleTurn(encounterID: Int,
                                    request: DriftBottleTurnRequest) async throws -> DriftBottleTurnResponse {
        let response: DriftBottleTurnResponse = try await call(
            "\(driftBottlePath)/encounters/\(encounterID)/turns", method: "POST", body: try encode(request))
        guard response.operation.requestID == request.requestID, response.encounter.id == encounterID else {
            throw APIError(status: 502, message: "服务器返回了不一致的请求编号")
        }
        return response
    }

    public func releaseDriftBottle(encounterID: Int,
                                   request: DriftBottleReleaseRequest) async throws -> DriftBottleReleaseResponse {
        let response: DriftBottleReleaseResponse = try await call(
            "\(driftBottlePath)/encounters/\(encounterID)/release", method: "POST", body: try encode(request))
        guard response.operation.requestID == request.requestID else {
            throw APIError(status: 502, message: "服务器返回了不一致的请求编号")
        }
        return response
    }

    public func generateDriftBottleMemory(encounterID: Int,
                                          request: DriftBottleMemoryRequest) async throws -> DriftBottleMemoryResponse {
        let response: DriftBottleMemoryResponse = try await call(
            "\(driftBottlePath)/encounters/\(encounterID)/memory", method: "POST", body: try encode(request))
        guard response.operation.requestID == request.requestID else {
            throw APIError(status: 502, message: "服务器返回了不一致的请求编号")
        }
        return response
    }

    public func driftBottleDraftSuggestion(_ request: DriftBottleDraftSuggestionRequest)
        async throws -> DriftBottleDraftSuggestionResponse {
        let response: DriftBottleDraftSuggestionResponse = try await call(
            driftBottlePath + "/draft-suggestions", method: "POST", body: try encode(request))
        guard response.operation.requestID == request.requestID else {
            throw APIError(status: 502, message: "服务器返回了不一致的请求编号")
        }
        return response
    }

    public func driftBottleRecords(botID: Int?, cursor: String?, limit: Int)
        async throws -> DriftBottleRecordsResponse {
        var query: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let botID { query.append(.init(name: "bot_id", value: String(botID))) }
        if let cursor, !cursor.isEmpty { query.append(.init(name: "cursor", value: cursor)) }
        return try await call(driftBottlePath + "/records", query: query)
    }

    public func driftBottleRecord(id: String) async throws -> DriftBottleRecord {
        try await call("\(driftBottlePath)/records/\(id)")
    }

    public func patchDriftBottleMemory(recordID: String, requestID: String,
                                       patch: DriftBottleMemoryPatch) async throws -> DriftBottleMemoryResponse {
        try await call("\(driftBottlePath)/records/\(recordID)/memory",
                       method: "PATCH", body: try encode(patch),
                       query: [.init(name: "request_id", value: requestID)])
    }

    public func deleteDriftBottleMemory(recordID: String, requestID: String)
        async throws -> DriftBottleDeleteResponse {
        try await call("\(driftBottlePath)/records/\(recordID)/memory", method: "DELETE",
                       query: [.init(name: "request_id", value: requestID)])
    }

    public func deleteDriftBottleRecord(id: String, requestID: String)
        async throws -> DriftBottleDeleteResponse {
        try await call("\(driftBottlePath)/records/\(id)", method: "DELETE",
                       query: [.init(name: "request_id", value: requestID)])
    }

    public func withdrawDriftBottleContribution(id: Int,
                                                request: DriftBottleWithdrawRequest) async throws -> DriftBottleWithdrawResponse {
        let response: DriftBottleWithdrawResponse = try await call(
            "\(driftBottlePath)/contributions/\(id)/withdraw", method: "POST", body: try encode(request))
        guard response.operation.requestID == request.requestID else {
            throw APIError(status: 502, message: "服务器返回了不一致的请求编号")
        }
        return response
    }

    public func reportDriftBottleContribution(_ request: DriftBottleReportRequest)
        async throws -> DriftBottleReportResponse {
        let response: DriftBottleReportResponse = try await call(
            driftBottlePath + "/reports", method: "POST", body: try encode(request))
        guard response.operation.requestID == request.requestID else {
            throw APIError(status: 502, message: "服务器返回了不一致的请求编号")
        }
        return response
    }

    public func blockDriftBottleContributor(_ request: DriftBottleBlockRequest)
        async throws -> DriftBottleBlockResponse {
        let response: DriftBottleBlockResponse = try await call(
            driftBottlePath + "/blocks", method: "POST", body: try encode(request))
        guard response.operation.requestID == request.requestID else {
            throw APIError(status: 502, message: "服务器返回了不一致的请求编号")
        }
        return response
    }

    public func driftBottleOperation(requestID: String) async throws -> DriftBottleOperationEnvelope {
        try await call(driftBottlePath + "/operations/\(requestID)")
    }
}
