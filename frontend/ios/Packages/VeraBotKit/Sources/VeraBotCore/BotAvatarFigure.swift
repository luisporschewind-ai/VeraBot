// 默认 Bot 形象：头像实验室的五款角色。无相册照片时 iOS 用它画头像；有照片时照片优先。
// `rawValue` 写入已有字段 `bots.avatar`（后端 max_length = 8），不新增 JSON 键。旧数据仍是表情。
import Foundation

public enum BotAvatarFigure: String, CaseIterable, Sendable, Identifiable, Codable {
    case veraBean
    case sprout
    case star
    case cloud
    case sugar

    /// 与 `BotIn.avatar` / `BotPatch.avatar` 的 `max_length` 一致。契约测试 AV-18 会核对。
    public static let maxStoredLength = 8

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .veraBean: "V豆"
        case .sprout: "芽芽"
        case .star: "星点"
        case .cloud: "云朵"
        case .sugar: "方糖"
        }
    }

    /// 新建 Bot 的默认形象。
    public static let `default` = BotAvatarFigure.veraBean

    /// 已保存的 `avatar`：形象 id 优先；旧表情按 `BotLook.emojis` 的位置对应五款形象；其余稳定映射。
    public init(stored avatar: String) {
        if let known = BotAvatarFigure(rawValue: avatar) {
            self = known
            return
        }
        if let index = BotLook.emojis.firstIndex(of: avatar) {
            self = Self.allCases[index % Self.allCases.count]
            return
        }
        let sum = avatar.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        self = Self.allCases[sum % Self.allCases.count]
    }

    /// 纯文字位置（协作记录标题等）：形象 id 显示中文名，旧表情保持原样。
    public static func textLabel(stored: String?) -> String {
        guard let stored, !stored.isEmpty else { return Self.default.title }
        if let known = Self(rawValue: stored) { return known.title }
        return stored
    }
}

/// 执行状态机的 10 种状态收成头像的 8 种姿态。界面色和动画仍在 App 的 `AvatarLabState`。
public enum BotAvatarPose: String, CaseIterable, Sendable, Hashable {
    case idle
    case thinking
    case working
    case delegating
    case replying
    case waiting
    case done
    case blocked

    public init(_ state: ExecutionState) {
        switch state {
        case .idle: self = .idle
        case .recalling, .thinking: self = .thinking
        case .callingTool: self = .working
        case .delegating: self = .delegating
        case .replying: self = .replying
        case .awaitingConfirmation: self = .waiting
        case .completed: self = .done
        case .blocked, .failed: self = .blocked
        }
    }
}

/// 相册照片优先于默认形象。
public enum BotAvatarDisplay: Equatable, Sendable {
    case photo
    case figure(BotAvatarFigure)

    public init(hasPhoto: Bool, storedAvatar: String) {
        if hasPhoto {
            self = .photo
        } else {
            self = .figure(BotAvatarFigure(stored: storedAvatar))
        }
    }
}
