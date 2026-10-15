import SwiftUI
import VeraBotCore

struct BotHomeView: View {
    @State private var profile: Bot
    let onSaved: @MainActor (Bot)->Void
    let onStartChat: @MainActor ()->Void
    let clearDisabled: Bool
    let onClear: @MainActor (Bool) async -> Void
    init(bot:Bot,onSaved:@escaping @MainActor(Bot)->Void,onStartChat:@escaping @MainActor()->Void,clearDisabled:Bool,onClear:@escaping @MainActor(Bool) async->Void) {
        _profile=State(initialValue:bot);self.onSaved=onSaved;self.onStartChat=onStartChat;self.clearDisabled=clearDisabled;self.onClear=onClear
    }
    var body: some View {
        BotEditView(bot: profile, onSaved: { profile = $0; onSaved($0) }, infoMode: true,
                    clearDisabled: clearDisabled, onClear: onClear)
    }
}
