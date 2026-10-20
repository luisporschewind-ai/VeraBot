import Foundation

// Deterministic presentation rules shared by the iOS views and tests.
// The server remains authoritative; these checks prevent an avoidable round-trip
// and keep the public/private boundary visible in the UI.

public enum DriftBottleBotAvailability: Equatable, Sendable {
    case ready
    case traveling
    case missing

    public var canStart: Bool { self == .ready }

    public var message: String {
        switch self {
        case .ready: ""
        case .traveling: "这位 Bot 还在旅途中，先等它回来"
        case .missing: "这位 Bot 已经不在了，换一位同行吧"
        }
    }
}

public struct DriftBottlePublicPreview: Equatable, Sendable {
    public let text: String
    public let authorship: DriftBottleAuthorship
    public let botName: String
    public let authorshipLabel: String
    public let boundaryNotice: String
    public let characterCount: Int

    public var isReadyToPublish: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...DriftBottlePresentation.maxPublicLength).contains(characterCount)
    }
}

public enum DriftBottlePresentation {
    public static let maxPublicLength = 1000
    public static let openingMaxLength = 120
    public static let chatMaxLength = 300
    public static let publicBoundaryNotice = "只有你确认的这段文字会随瓶漂流；你和 Bot 的私人交流不会公开。"
    public static let publicAudienceNotice = "后续捞到这个瓶子的人都能读到这段文字。"
    public static let firstPublicNameNotice = "这个 Bot 名字和头像会随公开留言展示，但不会展示你的账号。"

    public static func characterCount(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    public static func validatePublic(_ text: String) -> String? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "写下一句话再放漂吧"
        }
        let count = characterCount(text)
        if count > maxPublicLength {
            return "公开文字最多 \(maxPublicLength) 个字符，现在是 \(count) 个"
        }
        return nil
    }

    public static func validateChat(_ text: String) -> String? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "想说什么都可以，或者安静读一会儿"
        }
        if characterCount(text) > chatMaxLength {
            return "单条消息最多 \(chatMaxLength) 个字符"
        }
        return nil
    }

    public static func canPublish(text: String, endedAt: Double?, expiresAt: Double,
                                  now: Date) -> Bool {
        guard validatePublic(text) == nil, endedAt == nil else { return false }
        return now.timeIntervalSince1970 < expiresAt
    }

    public static func canPublish(encounter: DriftBottleEncounter, now: Date) -> Bool {
        guard !encounter.isExpired, !encounter.botDeleted else { return false }
        return canPublish(text: "x", endedAt: encounter.endedAt,
                          expiresAt: encounter.expiresAt, now: now)
    }

    public static func publicPreview(text: String, authorship: DriftBottleAuthorship,
                                     botName: String) -> DriftBottlePublicPreview {
        DriftBottlePublicPreview(
            text: text,
            authorship: authorship,
            botName: botName,
            authorshipLabel: authorship.label,
            boundaryNotice: publicBoundaryNotice + "\n" + publicAudienceNotice,
            characterCount: characterCount(text))
    }

    /// A generated draft is never silently presented as the owner's own words.
    public static func authorshipAfterGeneration(_ current: DriftBottleAuthorship)
        -> DriftBottleAuthorship {
        current == .owner ? .botDraft : current
    }

    public static func factualMemoryTitle(hasChat: Bool, botName: String) -> String {
        hasChat ? "我们一起读了一封信，聊了一会儿" : "我们一起读了一封信"
    }

    public static func botAvailability(bot: Bot?, traveling: Bool) -> DriftBottleBotAvailability {
        guard bot != nil else { return .missing }
        return traveling ? .traveling : .ready
    }

    public static func remainingText(seconds: Int) -> String {
        if seconds <= 0 { return "已到期" }
        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes == 0 ? "\(hours) 小时后到期" : "\(hours) 小时 \(minutes) 分后到期"
        }
        return "\(max(1, seconds / 60)) 分钟后到期"
    }

    public static func remainingText(until timestamp: Double, now: Date) -> String {
        remainingText(seconds: Int(max(0, timestamp - now.timeIntervalSince1970)))
    }
}
