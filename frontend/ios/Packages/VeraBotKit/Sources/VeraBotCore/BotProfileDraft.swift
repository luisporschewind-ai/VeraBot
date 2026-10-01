// Bot 详情顶部卡片的待保存改动（昵称、标签、相册照片）。只在点「保存」时提交，「取消」直接丢弃。
// 昵称规则与后端 `_clean_name` 一致：去首尾空白后不能为空，最多 20 个字（按 Unicode 码点，与 Python `len` 对齐）。
import Foundation

/// 相册照片的待保存操作。
public enum PendingBotPhoto: Equatable, Sendable {
    case unchanged
    /// 已压缩好的 JPEG，保存时 `POST /api/bots/{id}/avatar`
    case replace(Data)
    /// 恢复默认形象，保存时 `DELETE /api/bots/{id}/avatar`
    case remove
}

public struct BotProfileDraft: Equatable, Sendable {
    public static let maxNameLength = 20

    public let savedName: String
    public let savedTags: [String]
    public let savedHasPhoto: Bool
    public private(set) var name: String
    public private(set) var tags: [String]
    public private(set) var photo: PendingBotPhoto = .unchanged

    public init(bot: Bot) {
        savedName = bot.name
        savedTags = bot.tags
        savedHasPhoto = bot.hasAvatar
        name = bot.name
        tags = bot.tags
    }

    /// 卡片当前（含未保存改动）是否显示相册照片。
    public var showsPhoto: Bool {
        switch photo {
        case .unchanged: return savedHasPhoto
        case .replace: return true
        case .remove: return false
        }
    }

    /// 「使用默认形象」只在当前有照片时出现。
    public var canUseDefaultLook: Bool { showsPhoto }

    /// 标签编辑框的初始值：「搜索, 查询, 调研」。
    public var tagsText: String { BotTagRules.display(tags) }

    public var isDirty: Bool { name != savedName || tags != savedTags || photo != .unchanged }

    /// 修改昵称。返回错误文案时保留原值。
    @discardableResult
    public mutating func rename(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "昵称不能为空" }
        if trimmed.unicodeScalars.count > Self.maxNameLength { return "昵称最多 \(Self.maxNameLength) 个字" }
        name = trimmed
        return nil
    }

    /// 修改标签（与创建页同一套 `BotTagRules`）。返回错误文案时保留原值。
    @discardableResult
    public mutating func setTags(_ text: String) -> String? {
        let parsed = BotTagRules.parse(text)
        if let error = parsed.error { return error }
        tags = parsed.tags
        return nil
    }

    public mutating func choosePhoto(_ jpeg: Data) {
        photo = .replace(jpeg)
    }

    /// 已保存的照片 → 保存时删除；仅是未保存的新照片 → 直接撤销。
    public mutating func useDefaultLook() {
        photo = savedHasPhoto ? .remove : .unchanged
    }
}

/// 默认形象（表情 + 底色）的可选项，创建页与 Bot 详情共用。
public enum BotLook {
    public static let emojis = ["🤖", "🦊", "🐼", "🐱", "🦉", "🐧", "🦄", "🐙", "🌟", "🧠", "📚", "🔬", "💼", "🎨", "🍀", "☕"]
    public static let colors = ["#0f766e", "#14b8a6", "#0369a1", "#334155", "#059669", "#d97706", "#e11d48", "#78716c"]

    /// 后端默认色是大写（#0F766E），比较时忽略大小写。
    public static func sameColor(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
}

extension ToolInfo {
    /// 界面上的工具名：后端 `label`；缺失、为空或只是原始工具名时显示「未命名工具」，不露出英文标识。
    public var displayName: String {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty, label != name else { return "未命名工具" }
        return label
    }
}
