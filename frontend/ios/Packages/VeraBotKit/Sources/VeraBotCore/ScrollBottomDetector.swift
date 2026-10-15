// 对话列表是否贴底：私聊 / 群聊共用，决定「回到最新」按钮显隐与新消息自动跟随。
import CoreGraphics

public enum ScrollBottomDetector {
    public static let defaultTolerance: CGFloat = 40

    /// `anchor` 为内容末尾锚点的矩形，`viewport` 为可见区域（不含输入栏），两者须在同一坐标空间。
    /// 锚点顶边不低于视口底边 + `tolerance` 即贴底；回弹越过底部时锚点在视口上方，同样算贴底。
    public static func isNearBottom(anchor: CGRect, viewport: CGRect, tolerance: CGFloat = defaultTolerance) -> Bool {
        anchor.minY <= viewport.maxY + tolerance
    }

    /// 视口或锚点尚未测量（`.zero` / 空视口）时保留 `current`，不把未测量当成贴底或离底。
    public static func followsBottom(anchor: CGRect, viewport: CGRect, current: Bool,
                                     tolerance: CGFloat = defaultTolerance) -> Bool {
        guard viewport.height > 0, anchor != .zero else { return current }
        return isNearBottom(anchor: anchor, viewport: viewport, tolerance: tolerance)
    }
}
