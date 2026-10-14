// 产品层 Bot / 群聊数量上限（仅 UI 校验）。数值集中在此，便于日后改为远端动态配置。
import Foundation

public enum BotProductLimits {
    public static let maxBotsPerAccount = 10
    public static let minBotsPerGroup = 2
    public static let maxBotsPerGroup = 5

    /// 达账号 Bot 上限时的固定提示文案。
    public static let accountLimitReachedMessage =
        "最多可创建 \(maxBotsPerAccount) 个 Bot，请删除不再使用的 Bot 后重试。"

    /// 群聊创建页说明文案。
    public static let groupSelectionHint =
        "每个群聊需要选择 \(minBotsPerGroup)～\(maxBotsPerGroup) 个 Bot"

    /// 群聊满额时点击未选 Bot 的提示。
    public static let groupSelectionFullMessage =
        "每个群聊最多选择 \(maxBotsPerGroup) 个 Bot"

    public static func canCreateBot(currentCount: Int) -> Bool {
        currentCount < maxBotsPerAccount
    }

    public static func canAddBotToSelection(selectedCount: Int) -> Bool {
        selectedCount < maxBotsPerGroup
    }

    public static func canCreateGroup(selectedBotCount: Int) -> Bool {
        (minBotsPerGroup...maxBotsPerGroup).contains(selectedBotCount)
    }

    /// 成员编辑：是否允许再添加一名 Bot（历史超限群禁止继续添加）。
    public static func canAddMember(currentBotCount: Int) -> Bool {
        currentBotCount < maxBotsPerGroup
    }

    /// 成员编辑：是否允许再移除一名 Bot（不足下限时禁止移除）。
    public static func canRemoveMember(currentBotCount: Int) -> Bool {
        currentBotCount > minBotsPerGroup
    }

    /// 列表/管理页标题：`我的 Bot（7/10）`。
    public static func accountListTitle(botCount: Int) -> String {
        "我的 Bot（\(botCount)/\(maxBotsPerAccount)）"
    }

    /// 群聊选择区标题：`已选择 3/5 个 Bot`。
    public static func groupSelectionTitle(selectedCount: Int) -> String {
        "已选择 \(selectedCount)/\(maxBotsPerGroup) 个 Bot"
    }

    /// 只统计 Bot 成员（有 `botID` 的），不计真人/系统角色。
    public static func botMemberCount(in members: [ChatGroupMember]) -> Int {
        members.filter { $0.botID != nil }.count
    }
}
