import SwiftUI
import VeraBotCore

/// Preserve the original Bot profile form; its library tabs share the existing header.
struct BotInfoView: View {
    let vm: ChatViewModel
    var body: some View {
        BotEditView(bot: vm.bot, onSaved: { vm.bot = $0 }, infoMode: true,
                    clearDisabled: vm.sending,
                    onClear: { await vm.clear(includeMemories: $0) })
    }
}
