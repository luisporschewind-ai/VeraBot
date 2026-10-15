import Foundation
import Testing
@testable import VeraBotCore

@Test func botProductLimitsConstants() {
    #expect(BotProductLimits.maxBotsPerAccount == 10)
    #expect(BotProductLimits.minBotsPerGroup == 2)
    #expect(BotProductLimits.maxBotsPerGroup == 5)
}

@Test func botProductLimitsAccountCreateBoundary() {
    #expect(BotProductLimits.canCreateBot(currentCount: 0))
    #expect(BotProductLimits.canCreateBot(currentCount: 9))
    #expect(!BotProductLimits.canCreateBot(currentCount: 10))
    #expect(!BotProductLimits.canCreateBot(currentCount: 11))
    #expect(BotProductLimits.accountListTitle(botCount: 7) == "我的 Bot（7/10）")
    #expect(BotProductLimits.accountLimitReachedMessage
            == "最多可创建 10 个 Bot，请删除不再使用的 Bot 后重试。")
}

@Test func botProductLimitsGroupSelectionBoundary() {
    #expect(!BotProductLimits.canCreateGroup(selectedBotCount: 0))
    #expect(!BotProductLimits.canCreateGroup(selectedBotCount: 1))
    #expect(BotProductLimits.canCreateGroup(selectedBotCount: 2))
    #expect(BotProductLimits.canCreateGroup(selectedBotCount: 5))
    #expect(!BotProductLimits.canCreateGroup(selectedBotCount: 6))

    #expect(BotProductLimits.canAddBotToSelection(selectedCount: 4))
    #expect(!BotProductLimits.canAddBotToSelection(selectedCount: 5))
    #expect(BotProductLimits.groupSelectionTitle(selectedCount: 3) == "已选择 3/5 个 Bot")
    #expect(BotProductLimits.groupSelectionFullMessage == "每个群聊最多选择 5 个 Bot")
}

@Test func botProductLimitsMemberEditBoundary() {
    #expect(BotProductLimits.canAddMember(currentBotCount: 4))
    #expect(!BotProductLimits.canAddMember(currentBotCount: 5))
    #expect(!BotProductLimits.canAddMember(currentBotCount: 6))
    #expect(BotProductLimits.canRemoveMember(currentBotCount: 3))
    #expect(!BotProductLimits.canRemoveMember(currentBotCount: 2))
    #expect(!BotProductLimits.canRemoveMember(currentBotCount: 1))
}

@Test func botProductLimitsCountsOnlyBots() {
    let members = [
        ChatGroupMember(id: 1, botID: 10, name: "A", color: "#000", detail: ""),
        ChatGroupMember(id: 2, botID: 11, name: "B", color: "#000", detail: ""),
        ChatGroupMember(id: 3, botID: nil, name: "系统", color: "#000", detail: "", available: false),
    ]
    #expect(BotProductLimits.botMemberCount(in: members) == 2)
}
