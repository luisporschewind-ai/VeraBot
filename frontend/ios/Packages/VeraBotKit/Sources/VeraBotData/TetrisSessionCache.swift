import CryptoKit
import Foundation
import VeraBotCore

public struct TetrisCacheScope: Codable, Equatable, Hashable, Sendable {
    public let server: String
    public let userID: Int
    public let clientID: String
    public init(server: String, userID: Int, clientID: String) {
        self.server = server.trimmingCharacters(in: .whitespacesAndNewlines); self.userID = userID; self.clientID = clientID
    }
}
public struct TetrisCacheRecord: Codable, Equatable, Sendable {
    public var remote: TetrisRemoteSession?
    public var pending: TetrisWrite?
    public var localSnapshot: TetrisState?
    public var uncertainAttempt: Bool
    public init(remote: TetrisRemoteSession?, pending: TetrisWrite?, localSnapshot: TetrisState?, uncertainAttempt: Bool = false) {
        self.remote = remote; self.pending = pending; self.localSnapshot = localSnapshot; self.uncertainAttempt = uncertainAttempt
    }
}
public protocol TetrisSessionCaching: Sendable {
    func load(_ scope: TetrisCacheScope) async throws -> TetrisCacheRecord?
    func save(_ record: TetrisCacheRecord, scope: TetrisCacheScope) async throws
    func remove(_ scope: TetrisCacheScope) async throws
}
public actor TetrisSessionCache: TetrisSessionCaching {
    private struct Envelope: Codable { let version: Int; let scope: TetrisCacheScope; let record: TetrisCacheRecord; let checksum: String }
    private let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VeraBot/TetrisSessions", isDirectory: true)
    }
    @MainActor public static func installationClientID() -> String {
        let key = "tetris_installation_client_id"
        if let value = UserDefaults.standard.string(forKey: key), UUID(uuidString: value) != nil { return value }
        let value = UUID().uuidString; UserDefaults.standard.set(value, forKey: key); return value
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func path(_ scope: TetrisCacheScope) throws -> URL { directory.appendingPathComponent(hash(try encode(scope)) + ".json") }
    public func load(_ scope: TetrisCacheScope) throws -> TetrisCacheRecord? {
        let path = try path(scope)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 262144 else { throw TetrisSessionError.invalidContract }
        let data = try Data(contentsOf: path)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1, envelope.scope == scope,
              hash(try encode(envelope.record)) == envelope.checksum,
              envelope.record.pending == nil || envelope.record.pending?.clientID == scope.clientID else { throw TetrisSessionError.invalidContract }
        return envelope.record
    }
    public func save(_ record: TetrisCacheRecord, scope: TetrisCacheScope) throws {
        guard record.pending == nil || record.pending?.clientID == scope.clientID else { throw TetrisSessionError.invalidContract }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let envelope = Envelope(version: 1, scope: scope, record: record, checksum: hash(try encode(record)))
        let path = try path(scope)
        try encode(envelope).write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path.path)
        #endif
    }
    public func remove(_ scope: TetrisCacheScope) throws {
        let path = try path(scope)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
}
