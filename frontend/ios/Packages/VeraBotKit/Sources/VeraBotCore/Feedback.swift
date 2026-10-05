import Foundation

/// 消息反馈（记忆 M2 风格校准，后端 `message_feedback` 表 / `POST /api/messages/{id}/feedback`）。
/// 契约见 docs/design/MEMORY_GROWTH.md §11.1：👍 / 👎 只评本人的 assistant 消息，同一条可改可撤。

/// 👎 的理由（后端 reason 取值；👍 不带理由）。
public enum FeedbackReason: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case tooLong = "too_long"
    case tooShort = "too_short"
    case inaccurate
    case tone
    case other

    public var id: String { rawValue }

    /// 后端将来新增的理由不认识的按「其他」处理，不让整条消息解析失败。
    public init(from decoder: Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }

    /// 👎 后系统 confirmationDialog 里的选项文案（「哪里不满意？」）。
    public var title: String {
        switch self {
        case .tooLong: return "太长"
        case .tooShort: return "太短"
        case .inaccurate: return "不准确"
        case .tone: return "语气"
        case .other: return "其他"
        }
    }
}

/// 一条消息上的反馈：`rating` 1 = 👍、-1 = 👎；理由只在 👎 时有。
public struct MessageFeedback: Codable, Sendable, Hashable {
    public let rating: Int
    public let reason: FeedbackReason?

    public init(rating: Int, reason: FeedbackReason? = nil) {
        self.rating = rating
        self.reason = reason
    }

    /// 旧后端没有 reason 键 → nil，不崩。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rating = try c.decode(Int.self, forKey: .rating)
        reason = try c.decodeIfPresent(FeedbackReason.self, forKey: .reason)
    }
}

/// POST /api/messages/{id}/feedback 的响应。`proposal` 非空 = 本次评价刚好把同类 👎 聚合到阈值，
/// 服务器生成了 style 记忆提议（与 `remember` 工具结果同构），客户端就地渲染确认卡片。
public struct FeedbackResponse: Decodable, Sendable {
    public let ok: Bool
    public let messageID: Int
    public let rating: Int
    public let reason: FeedbackReason?
    /// 保留原始 JSON：卡片走 `ToolTrace.memoryProposal` 的既有解析，不重复一份字段映射。
    public let proposal: JSONValue?

    enum CodingKeys: String, CodingKey {
        case ok, rating, reason, proposal
        case messageID = "message_id"
    }

    /// 就地把提议渲染成确认卡片的合成 trace（与服务器在本轮回复后追加的 style 提议同一形状）。
    public var proposalTrace: ToolTrace? {
        guard let p = MemoryProposal(result: proposal), p.isCard else { return nil }
        return ToolTrace(id: "style_feedback_\(messageID)", name: "remember", args: nil, result: proposal)
    }
}
