import SwiftUI
import VeraBotCore

/// Bot 详情（Bot Info）：点击对话页标题，以系统默认 sheet 弹出（下滑关闭）。
/// 直接内嵌完整的 Bot 设置表单（基本信息、工具权限、委派、协作记录），底部为「清空对话」（二次确认，可选同时删除该 Bot 的记忆），右上角「保存」。
struct BotInfoView: View {
    let vm: ChatViewModel

    var body: some View {
        BotEditView(bot: vm.bot,
                    onSaved: { updated in vm.bot = updated },
                    infoMode: true,
                    clearDisabled: vm.sending,
                    onClear: { includeMemories in await vm.clear(includeMemories: includeMemories) })
    }
}
