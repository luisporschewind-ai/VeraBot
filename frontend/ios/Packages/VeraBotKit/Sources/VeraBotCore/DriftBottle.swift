import Foundation

// MARK: - Shared Drift Bottle contracts
//
// Mirrors backend `services/drift_bottle/contracts.py`. Public contribution DTOs
// deliberately carry only Bot display snapshots and a display state; author
// account IDs never cross the API boundary.

public enum DriftBottleAuthorship: String, Codable, CaseIterable, Sendable, Identifiable {
    case owner
    case coauthored
    case botDraft = "bot_draft"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .owner: "主人亲笔"
        case .coauthored: "与 Bot 合写"
        case .botDraft: "Bot 拟稿，主人确认"
        }
    }

    public var shortLabel: String {
        switch self {
        case .owner: "亲笔"
        case .coauthored: "合写"
        case .botDraft: "Bot 拟稿"
        }
    }
}

public enum DriftBottleContributionState: String, Codable, Sendable {
    case visible
    case withdrawn
    case hidden
}

public enum DriftBottleDisplayState: String, Codable, Sendable {
    case visible
    case withdrawn
    case hidden
    case reported
    case blocked

    public var isReadable: Bool { self == .visible }
}

public enum DriftBottleEndReason: String, Codable, Sendable {
    case returned
    case released
    case expired
}

public enum DriftBottleRecordKind: String, Codable, Sendable {
    case encounter
    case release
}

public enum DriftBottleTurnRole: String, Codable, Sendable {
    case user
    case bot
    case system
}

public enum DriftBottleTurnKind: String, Codable, Sendable {
    case opening
    case chat
    case draft
    case quiet
}

public enum DriftBottleOperationStatus: String, Codable, Sendable {
    case pending
    case committed
    case failed

    public var isFinal: Bool { self != .pending }
}

public struct DriftBottlePublicContribution: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let bottleID: Int
    public let sequence: Int
    public let kind: String
    public let body: String
    public let state: DriftBottleContributionState
    public let displayState: DriftBottleDisplayState
    public let botName: String
    public let botAvatar: String
    public let botColor: String
    public let authorship: DriftBottleAuthorship
    public let createdAt: Double
    public let isMine: Bool
    public let canWithdraw: Bool
    public let canReport: Bool

    public var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
    public var isReadable: Bool { displayState.isReadable }

    public init(id: Int, bottleID: Int, sequence: Int, kind: String, body: String,
                state: DriftBottleContributionState, displayState: DriftBottleDisplayState,
                botName: String, botAvatar: String, botColor: String,
                authorship: DriftBottleAuthorship, createdAt: Double,
                isMine: Bool = false, canWithdraw: Bool = false, canReport: Bool = false) {
        self.id = id
        self.bottleID = bottleID
        self.sequence = sequence
        self.kind = kind
        self.body = body
        self.state = state
        self.displayState = displayState
        self.botName = botName
        self.botAvatar = botAvatar
        self.botColor = botColor
        self.authorship = authorship
        self.createdAt = createdAt
        self.isMine = isMine
        self.canWithdraw = canWithdraw
        self.canReport = canReport
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bottleID = "bottle_id"
        case sequence, kind, body, state
        case displayState = "display_state"
        case botName = "bot_name"
        case botAvatar = "bot_avatar"
        case botColor = "bot_color"
        case authorship
        case createdAt = "created_at"
        case isMine = "is_mine"
        case canWithdraw = "can_withdraw"
        case canReport = "can_report"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        bottleID = try c.decode(Int.self, forKey: .bottleID)
        sequence = try c.decode(Int.self, forKey: .sequence)
        kind = try c.decode(String.self, forKey: .kind)
        body = try c.decode(String.self, forKey: .body)
        state = try c.decode(DriftBottleContributionState.self, forKey: .state)
        displayState = try c.decodeIfPresent(DriftBottleDisplayState.self, forKey: .displayState) ?? .visible
        botName = try c.decode(String.self, forKey: .botName)
        botAvatar = try c.decode(String.self, forKey: .botAvatar)
        botColor = try c.decode(String.self, forKey: .botColor)
        authorship = try c.decode(DriftBottleAuthorship.self, forKey: .authorship)
        createdAt = try c.decode(Double.self, forKey: .createdAt)
        isMine = try c.decodeIfPresent(Bool.self, forKey: .isMine) ?? false
        canWithdraw = try c.decodeIfPresent(Bool.self, forKey: .canWithdraw) ?? false
        canReport = try c.decodeIfPresent(Bool.self, forKey: .canReport) ?? false
    }
}

public struct DriftBottleTurn: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let role: DriftBottleTurnRole
    public let kind: DriftBottleTurnKind
    public let content: String
    public let createdAt: Double

    public var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
    public var isPrivate: Bool { kind == .opening || kind == .chat }

    public init(id: Int, role: DriftBottleTurnRole, kind: DriftBottleTurnKind,
                content: String, createdAt: Double) {
        self.id = id
        self.role = role
        self.kind = kind
        self.content = content
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, role, kind, content
        case createdAt = "created_at"
    }
}

public struct DriftBottleMemory: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let encounterID: Int
    public let recordID: String
    public let title: String
    public let summary: String
    public let ownerNote: String
    public let edited: Bool
    public let generatedBy: String
    public let sourceTurnIDs: [Int]
    public let version: Int
    public let createdAt: Double
    public let updatedAt: Double

    public var isBotGenerated: Bool { generatedBy == "bot" }

    public init(id: Int, encounterID: Int, recordID: String, title: String, summary: String,
                ownerNote: String, edited: Bool, generatedBy: String, sourceTurnIDs: [Int],
                version: Int, createdAt: Double, updatedAt: Double) {
        self.id = id
        self.encounterID = encounterID
        self.recordID = recordID
        self.title = title
        self.summary = summary
        self.ownerNote = ownerNote
        self.edited = edited
        self.generatedBy = generatedBy
        self.sourceTurnIDs = sourceTurnIDs
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case encounterID = "encounter_id"
        case recordID = "record_id"
        case title, summary
        case ownerNote = "owner_note"
        case edited
        case generatedBy = "generated_by"
        case sourceTurnIDs = "source_turn_ids"
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct DriftBottleLimits: Codable, Sendable, Hashable {
    public let maxContributionsPerBottle: Int
    public let holdSeconds: Int
    public let publicLengthMin: Int
    public let publicLengthMax: Int
    public let openingMaxLength: Int
    public let chatMaxLength: Int
    public let publishPerMinute: Int
    public let drawPerMinute: Int
    public let generatePerMinute: Int

    public static let standard = DriftBottleLimits(
        maxContributionsPerBottle: 50, holdSeconds: 86400, publicLengthMin: 1,
        publicLengthMax: 1000, openingMaxLength: 120, chatMaxLength: 300,
        publishPerMinute: 5, drawPerMinute: 10, generatePerMinute: 10)

    public init(maxContributionsPerBottle: Int, holdSeconds: Int, publicLengthMin: Int,
                publicLengthMax: Int, openingMaxLength: Int, chatMaxLength: Int,
                publishPerMinute: Int, drawPerMinute: Int, generatePerMinute: Int) {
        self.maxContributionsPerBottle = maxContributionsPerBottle
        self.holdSeconds = holdSeconds
        self.publicLengthMin = publicLengthMin
        self.publicLengthMax = publicLengthMax
        self.openingMaxLength = openingMaxLength
        self.chatMaxLength = chatMaxLength
        self.publishPerMinute = publishPerMinute
        self.drawPerMinute = drawPerMinute
        self.generatePerMinute = generatePerMinute
    }

    enum CodingKeys: String, CodingKey {
        case maxContributionsPerBottle = "max_contributions_per_bottle"
        case holdSeconds = "hold_seconds"
        case publicLengthMin = "public_length_min"
        case publicLengthMax = "public_length_max"
        case openingMaxLength = "opening_max_length"
        case chatMaxLength = "chat_max_length"
        case publishPerMinute = "publish_per_minute"
        case drawPerMinute = "draw_per_minute"
        case generatePerMinute = "generate_per_minute"
    }
}

public struct DriftBottleEncounter: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let bottleID: Int
    public let botID: Int?
    public let botName: String
    public let botAvatar: String
    public let botColor: String
    public let botDeleted: Bool
    public let startedAt: Double
    public let expiresAt: Double
    public let endedAt: Double?
    public let endReason: DriftBottleEndReason?
    public let version: Int
    public let bottleVersion: Int
    public let leaseToken: String
    public let readLimit: Int
    public let quiet: Bool
    public let remainingSeconds: Int
    public let isExpired: Bool
    public let canPublish: Bool
    public var contributions: [DriftBottlePublicContribution]
    public var nextCursor: String?
    public var turns: [DriftBottleTurn]
    public var memory: DriftBottleMemory?

    public var isActive: Bool { endedAt == nil && !isExpired }
    public var canChat: Bool { botID != nil }
    public var startedDate: Date { Date(timeIntervalSince1970: startedAt) }
    public var expiresDate: Date { Date(timeIntervalSince1970: expiresAt) }
    public var endedDate: Date? { endedAt.map(Date.init(timeIntervalSince1970:)) }

    public init(id: Int, bottleID: Int, botID: Int?, botName: String, botAvatar: String,
                botColor: String, botDeleted: Bool, startedAt: Double, expiresAt: Double,
                endedAt: Double?, endReason: DriftBottleEndReason?, version: Int,
                bottleVersion: Int, leaseToken: String, readLimit: Int, quiet: Bool,
                remainingSeconds: Int, isExpired: Bool, canPublish: Bool,
                contributions: [DriftBottlePublicContribution], nextCursor: String?,
                turns: [DriftBottleTurn], memory: DriftBottleMemory?) {
        self.id = id
        self.bottleID = bottleID
        self.botID = botID
        self.botName = botName
        self.botAvatar = botAvatar
        self.botColor = botColor
        self.botDeleted = botDeleted
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.version = version
        self.bottleVersion = bottleVersion
        self.leaseToken = leaseToken
        self.readLimit = readLimit
        self.quiet = quiet
        self.remainingSeconds = remainingSeconds
        self.isExpired = isExpired
        self.canPublish = canPublish
        self.contributions = contributions
        self.nextCursor = nextCursor
        self.turns = turns
        self.memory = memory
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bottleID = "bottle_id"
        case botID = "bot_id"
        case botName = "bot_name"
        case botAvatar = "bot_avatar"
        case botColor = "bot_color"
        case botDeleted = "bot_deleted"
        case startedAt = "started_at"
        case expiresAt = "expires_at"
        case endedAt = "ended_at"
        case endReason = "end_reason"
        case version
        case bottleVersion = "bottle_version"
        case leaseToken = "lease_token"
        case readLimit = "read_limit"
        case quiet
        case remainingSeconds = "remaining_seconds"
        case isExpired = "is_expired"
        case canPublish = "can_publish"
        case contributions
        case nextCursor = "next_cursor"
        case turns, memory
    }
}

public struct DriftBottleRelease: Codable, Sendable, Hashable {
    public let bottleID: Int
    public let state: String
    public let publicCount: Int
    public let createdAt: Double
    public let botID: Int?
    public let botName: String
    public let botAvatar: String
    public let botColor: String
    public let contributions: [DriftBottlePublicContribution]

    enum CodingKeys: String, CodingKey {
        case bottleID = "bottle_id"
        case state
        case publicCount = "public_count"
        case createdAt = "created_at"
        case botID = "bot_id"
        case botName = "bot_name"
        case botAvatar = "bot_avatar"
        case botColor = "bot_color"
        case contributions
    }
}

public struct DriftBottleRecordSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: DriftBottleRecordKind
    public let title: String
    public let subtitle: String
    public let botID: Int?
    public let botName: String
    public let botAvatar: String
    public let botColor: String
    public let createdAt: Double
    public let completedAt: Double?
    public let hasMemory: Bool
    public let contributionCount: Int

    public var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
    public var completedDate: Date? { completedAt.map(Date.init(timeIntervalSince1970:)) }
    public var isEncounter: Bool { kind == .encounter }

    public init(id: String, kind: DriftBottleRecordKind, title: String, subtitle: String,
                botID: Int?, botName: String, botAvatar: String, botColor: String,
                createdAt: Double, completedAt: Double?, hasMemory: Bool, contributionCount: Int) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.botID = botID
        self.botName = botName
        self.botAvatar = botAvatar
        self.botColor = botColor
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.hasMemory = hasMemory
        self.contributionCount = contributionCount
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle
        case botID = "bot_id"
        case botName = "bot_name"
        case botAvatar = "bot_avatar"
        case botColor = "bot_color"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case hasMemory = "has_memory"
        case contributionCount = "contribution_count"
    }
}

public struct DriftBottleRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: DriftBottleRecordKind
    public let title: String
    public let subtitle: String
    public let createdAt: Double
    public let completedAt: Double?
    public let encounter: DriftBottleEncounter?
    public let release: DriftBottleRelease?
    public let contributions: [DriftBottlePublicContribution]
    public let turns: [DriftBottleTurn]
    public let memory: DriftBottleMemory?

    public var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
    public var completedDate: Date? { completedAt.map(Date.init(timeIntervalSince1970:)) }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case encounter, release, contributions, turns, memory
    }
}

public struct DriftBottleState: Codable, Sendable, Hashable {
    public let serverTime: Double
    public let current: DriftBottleEncounter?
    public let limits: DriftBottleLimits
    public let hasActiveEncounter: Bool

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case current, limits
        case hasActiveEncounter = "has_active_encounter"
    }
}

public struct DriftBottleOperation: Codable, Sendable, Hashable, Identifiable {
    public let requestID: String
    public let status: DriftBottleOperationStatus
    public let kind: String
    public let errorCode: String?
    public let errorMessage: String?
    public let retryable: Bool

    public var id: String { requestID }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status, kind
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case retryable
    }
}

public struct DriftBottleOperationEnvelope: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let result: JSONValue?
}

// MARK: - Requests

public struct DriftBottleContributionInput: Codable, Sendable, Hashable {
    public var body: String
    public var authorship: DriftBottleAuthorship

    public init(body: String, authorship: DriftBottleAuthorship) {
        self.body = body
        self.authorship = authorship
    }
}

public struct DriftBottleCreateRequest: Codable, Sendable {
    public var requestID: String
    public var botID: Int
    public var body: String
    public var authorship: DriftBottleAuthorship

    public init(requestID: String, botID: Int, body: String, authorship: DriftBottleAuthorship) {
        self.requestID = requestID
        self.botID = botID
        self.body = body
        self.authorship = authorship
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case botID = "bot_id"
        case body, authorship
    }
}

public struct DriftBottleDrawRequest: Codable, Sendable {
    public var requestID: String
    public var botID: Int

    public init(requestID: String, botID: Int) {
        self.requestID = requestID
        self.botID = botID
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case botID = "bot_id"
    }
}

public struct DriftBottleReleaseRequest: Codable, Sendable {
    public var requestID: String
    public var leaseToken: String
    public var expectedVersion: Int
    public var contribution: DriftBottleContributionInput?

    public init(requestID: String, leaseToken: String, expectedVersion: Int,
                contribution: DriftBottleContributionInput?) {
        self.requestID = requestID
        self.leaseToken = leaseToken
        self.expectedVersion = expectedVersion
        self.contribution = contribution
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case leaseToken = "lease_token"
        case expectedVersion = "expected_version"
        case contribution
    }
}

public struct DriftBottleTurnRequest: Codable, Sendable {
    public var requestID: String
    public var kind: DriftBottleTurnKind
    public var text: String
    public var quiet: Bool

    public init(requestID: String, kind: DriftBottleTurnKind, text: String = "", quiet: Bool = false) {
        self.requestID = requestID
        self.kind = kind
        self.text = text
        self.quiet = quiet
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case kind, text, quiet
    }
}

public struct DriftBottleDraftSuggestionRequest: Codable, Sendable {
    public var requestID: String
    public var botID: Int
    public var body: String

    public init(requestID: String, botID: Int, body: String = "") {
        self.requestID = requestID
        self.botID = botID
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case botID = "bot_id"
        case body
    }
}

public struct DriftBottleMemoryRequest: Codable, Sendable {
    public var requestID: String

    public init(requestID: String) { self.requestID = requestID }

    enum CodingKeys: String, CodingKey { case requestID = "request_id" }
}

public struct DriftBottleMemoryPatch: Codable, Sendable {
    public var title: String?
    public var summary: String?
    public var ownerNote: String?
    public var expectedVersion: Int?

    public init(title: String? = nil, summary: String? = nil, ownerNote: String? = nil,
                expectedVersion: Int? = nil) {
        self.title = title
        self.summary = summary
        self.ownerNote = ownerNote
        self.expectedVersion = expectedVersion
    }

    enum CodingKeys: String, CodingKey {
        case title, summary
        case ownerNote = "owner_note"
        case expectedVersion = "expected_version"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(ownerNote, forKey: .ownerNote)
        try c.encodeIfPresent(expectedVersion, forKey: .expectedVersion)
    }
}

public struct DriftBottleWithdrawRequest: Codable, Sendable {
    public var requestID: String
    public init(requestID: String) { self.requestID = requestID }
    enum CodingKeys: String, CodingKey { case requestID = "request_id" }
}

public struct DriftBottleReportRequest: Codable, Sendable {
    public var requestID: String
    public var contributionID: Int
    public var reason: String

    public init(requestID: String, contributionID: Int, reason: String) {
        self.requestID = requestID
        self.contributionID = contributionID
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case contributionID = "contribution_id"
        case reason
    }
}

public struct DriftBottleBlockRequest: Codable, Sendable {
    public var requestID: String
    public var contributionID: Int

    public init(requestID: String, contributionID: Int) {
        self.requestID = requestID
        self.contributionID = contributionID
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case contributionID = "contribution_id"
    }
}

// MARK: - Responses

public struct DriftBottleCreateResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let record: DriftBottleRecordSummary
}

public struct DriftBottleDrawResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let encounter: DriftBottleEncounter?
}

public struct DriftBottleReleaseResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let record: DriftBottleRecord
}

public struct DriftBottleTurnResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let encounter: DriftBottleEncounter
    public let turn: DriftBottleTurn?
    public let draft: String?
}

public struct DriftBottleDraftSuggestionResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let draft: String
    public let authorship: DriftBottleAuthorship
}

public struct DriftBottleMemoryResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let memory: DriftBottleMemory
}

public struct DriftBottleRecordsResponse: Codable, Sendable {
    public let records: [DriftBottleRecordSummary]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextCursor = "next_cursor"
    }
}

public struct DriftBottleWithdrawResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let contribution: DriftBottlePublicContribution
}

public struct DriftBottleReportInfo: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let contributionID: Int
    public let state: String
    public let createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id
        case contributionID = "contribution_id"
        case state
        case createdAt = "created_at"
    }
}

public struct DriftBottleReportResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let report: DriftBottleReportInfo
}

public struct DriftBottleBlockResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let blocked: Bool
}

public struct DriftBottleDeleteResponse: Codable, Sendable {
    public let operation: DriftBottleOperation
    public let deleted: Bool
}

// Result shapes fetched from `GET /operations/{request_id}`. The operation
// itself is returned alongside `result`, so these payloads contain only the
// resource produced by the original endpoint.
public struct DriftBottleReleaseResult: Codable, Sendable {
    public let record: DriftBottleRecord

    public init(record: DriftBottleRecord) { self.record = record }
}

public struct DriftBottleTurnResult: Codable, Sendable {
    public let encounter: DriftBottleEncounter
    public let turn: DriftBottleTurn?
    public let draft: String?

    public init(encounter: DriftBottleEncounter, turn: DriftBottleTurn?, draft: String?) {
        self.encounter = encounter
        self.turn = turn
        self.draft = draft
    }
}

public extension DriftBottleRecord {
    /// A new record value after a private turn; public contributions are unchanged.
    func appending(turn: DriftBottleTurn) -> DriftBottleRecord {
        DriftBottleRecord(id: id, kind: kind, title: title, subtitle: subtitle,
                          createdAt: createdAt, completedAt: completedAt,
                          encounter: encounter, release: release,
                          contributions: contributions, turns: turns + [turn], memory: memory)
    }

    func replacing(memory: DriftBottleMemory?) -> DriftBottleRecord {
        DriftBottleRecord(id: id, kind: kind, title: title, subtitle: subtitle,
                          createdAt: createdAt, completedAt: completedAt,
                          encounter: encounter, release: release,
                          contributions: contributions, turns: turns, memory: memory)
    }
}
