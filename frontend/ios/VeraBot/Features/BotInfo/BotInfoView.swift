import SwiftUI
import VeraBotCore

/// Bot home owns navigation; editing keeps the existing explicit-save form.
struct BotInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let vm: ChatViewModel
    var body: some View {
        BotHomeView(bot:vm.bot,onSaved:{vm.bot=$0},onStartChat:{dismiss()},clearDisabled:vm.sending,onClear:{includeMemories in await vm.clear(includeMemories:includeMemories)})
    }
}
