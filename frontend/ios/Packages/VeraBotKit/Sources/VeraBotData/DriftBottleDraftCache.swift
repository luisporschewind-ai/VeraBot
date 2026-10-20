import Foundation
import CryptoKit
import VeraBotCore

// Account-scoped local cache. It intentionally stores only the owner's private
// turns, their own drafts and operation identifiers. Other people's letter and
// message bodies are never written here; offline reading shows a "waiting for
// network" state instead of stale public text.

public struct DriftBottleDraft: Codable, Sendable, Hashable {
    public var text: String
    public var authorship: DriftBottleAuthorship
    public var generated: Bool
    public var updatedAt: Date
    public var encounterID: Int?
    public var bottleID: Int?

    public init(text: String, authorship: DriftBottleAuthorship, generated: Bool,
                updatedAt: Date, encounterID: Int? = nil, bottleID: Int? = nil) {
        self.text = text
        self.authorship = authorship
        self.generated = generated
        self.updatedAt = updatedAt
        self.encounterID = encounterID
        self.bottleID = bottleID
    }
}

public struct DriftBottleCachedEncounter: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let bottleID: Int
    public let botID: Int?
    public let botName: String
    public let botAvatar: String
    public let botColor: String
    public let readLimit: Int
    public let expiresAt: Double
    public let endedAt: Double?
    public let endReason: DriftBottleEndReason?
    public let turns: [DriftBottleTurn]

    public init(id: Int, bottleID: Int, botID: Int?, botName: String, botAvatar: String,
                botColor: String, readLimit: Int, expiresAt: Double, endedAt: Double?,
                endReason: DriftBottleEndReason?, turns: [DriftBottleTurn]) {
        self.id = id
        self.bottleID = bottleID
        self.botID = botID
        self.botName = botName
        self.botAvatar = botAvatar
        self.botColor = botColor
        self.readLimit = readLimit
        self.expiresAt = expiresAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.turns = turns
    }

    public init(encounter: DriftBottleEncounter) {
        self.init(id: encounter.id, bottleID: encounter.bottleID, botID: encounter.botID,
                  botName: encounter.botName, botAvatar: encounter.botAvatar,
                  botColor: encounter.botColor, readLimit: encounter.readLimit,
                  expiresAt: encounter.expiresAt, endedAt: encounter.endedAt,
                  endReason: encounter.endReason, turns: encounter.turns)
    }
}

public enum DriftBottlePendingKind: String, Codable, Sendable {
    case release
    case chat
}

public struct DriftBottlePendingOperation: Codable, Sendable, Hashable, Identifiable {
    public let requestID: String
    public let kind: DriftBottlePendingKind
    public let encounterID: Int
    public let text: String?

    public var id: String { requestID }

    public init(requestID: String, kind: DriftBottlePendingKind, encounterID: Int,
                text: String? = nil) {
        self.requestID = requestID
        self.kind = kind
        self.encounterID = encounterID
        self.text = text
    }
}

public struct DriftBottleLocalRecord: Codable, Sendable {
    public var scope: String
    public var selectedBotID: Int?
    public var activeEncounter: DriftBottleCachedEncounter?
    public var drafts: [String: DriftBottleDraft]
    public var pendingOperations: [DriftBottlePendingOperation]

    public init(scope: String, selectedBotID: Int?, activeEncounter: DriftBottleCachedEncounter?,
                drafts: [String: DriftBottleDraft], pendingOperations: [DriftBottlePendingOperation]) {
        self.scope = scope
        self.selectedBotID = selectedBotID
        self.activeEncounter = activeEncounter
        self.drafts = drafts
        self.pendingOperations = pendingOperations
    }
}

public actor DriftBottleDraftCache {
    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = base.appendingPathComponent("VeraBot/DriftBottle", isDirectory: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    public nonisolated static func fileStem(scope: String) -> String {
        let digest = SHA256.hash(data: Data(scope.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func load(scope: String) throws -> DriftBottleLocalRecord? {
        let url = fileURL(scope: scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(DriftBottleLocalRecord.self, from: data)
    }

    public func save(_ record: DriftBottleLocalRecord, scope: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(values)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: root.path)
        let data = try encoder.encode(record)
        let url = fileURL(scope: scope)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path)
    }

    public func clear(scope: String) {
        try? FileManager.default.removeItem(at: fileURL(scope: scope))
    }

    private func fileURL(scope: String) -> URL {
        root.appendingPathComponent(Self.fileStem(scope: scope) + ".json")
    }
}
