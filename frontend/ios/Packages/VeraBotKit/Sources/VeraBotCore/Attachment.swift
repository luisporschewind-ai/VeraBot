import Foundation

/// 图片附件（后端 schema v12，`/api/attachments`）。字段与后端 `services/attachments/repo.py` 的 `public()` 一一对应，
/// 契约测试 ATT-CONTRACT（backend/scripts/test/attachments_test.py）读取这里的 CodingKeys 断言一致。
public struct Attachment: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: String          // 目前只有 "image"
    public let mime: String          // image/jpeg / image/png / image/gif
    public let width: Int
    public let height: Int
    public let bytes: Int
    public let status: String        // pending（已上传未发送）/ attached（已随消息发送）
    public let expiresAt: String?    // 仅 pending：过期后服务器删除

    enum CodingKeys: String, CodingKey {
        case id, kind, mime, width, height, bytes, status
        case expiresAt = "expires_at"
    }

    public init(id: String, kind: String = "image", mime: String, width: Int, height: Int, bytes: Int,
                status: String, expiresAt: String? = nil) {
        self.id = id
        self.kind = kind
        self.mime = mime
        self.width = width
        self.height = height
        self.bytes = bytes
        self.status = status
        self.expiresAt = expiresAt
    }

    public var isGIF: Bool { mime == "image/gif" }

    /// 宽高比（高 / 宽），尺寸异常时按正方形处理。
    public var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }
        return Double(height) / Double(width)
    }
}

/// 客户端侧的限制（与后端一致；后端仍会再校验）。
public enum AttachmentLimits {
    public static let maxPerMessage = 1
    public static let maxBytes = 10 * 1024 * 1024
    public static let maxSide = 2048
    public static let jpegQuality = 0.8

    /// 按文件头判断 GIF（GIF 原样上传，保留动画）。
    public static func isGIF(_ data: Data) -> Bool {
        data.count >= 6 && (data.prefix(6) == Data("GIF89a".utf8) || data.prefix(6) == Data("GIF87a".utf8))
    }

    /// 按文件头取扩展名（gif / png / jpg），用于写 Quick Look 预览文件：系统按扩展名识别类型，GIF 必须是 .gif 才播放动画。
    public static func fileExtension(for data: Data) -> String {
        if isGIF(data) { return "gif" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        return "jpg"
    }
}

/// POST /api/bots/{id}/chat 请求体。`attachment_ids` 最多 1 个；有图时 message 可以为空。
public struct ChatRequest: Encodable, Sendable {
    public let message: String
    public let attachmentIDs: [String]

    enum CodingKeys: String, CodingKey {
        case message
        case attachmentIDs = "attachment_ids"
    }

    public init(message: String, attachmentIDs: [String] = []) {
        self.message = message
        self.attachmentIDs = attachmentIDs
    }
}

extension ChatMessage {
    /// 旧后端没有 attachments（v12 起）/ feedback（v14 起）键：按空数组 / nil 处理，不崩。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        role = try c.decode(String.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        traces = try c.decodeIfPresent([ToolTrace].self, forKey: .traces)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        feedback = try c.decodeIfPresent(MessageFeedback.self, forKey: .feedback)
    }
}
