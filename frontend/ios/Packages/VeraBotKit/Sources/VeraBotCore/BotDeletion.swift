// 删除 Bot 的二次确认文案。内容与后端 `DELETE /api/bots/{id}` 的实际效果一致（见 TEST_CASES BOTDEL-*）：
// 级联删除 messages、scope=bot/summary 的记忆、照片头像（触发器）、Bot 自身的工具 / 委派 / 记忆授权设置，
// 并从其他 Bot 的 delegate_to 中移除；保留 global 记忆（source_bot_id 置空）、提醒（bot_id 置空）、协作记录与用量记录。
import Foundation

public enum BotDeletion {
    public static func title(_ name: String) -> String {
        "删除「\(name)」？"
    }

    public static func message(_ name: String) -> String {
        "将删除与「\(name)」的全部对话、仅它可用的记忆和对话摘要、它的照片头像和权限设置，并把它从其他 Bot 的委派名单中移除。"
            + "所有 Bot 共享的资料、它创建的提醒、协作记录和用量统计会保留。此操作无法撤销。"
    }
}
