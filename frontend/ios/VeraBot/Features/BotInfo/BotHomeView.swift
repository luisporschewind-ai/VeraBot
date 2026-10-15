import SwiftUI
import VeraBotCore

struct BotHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var profile: Bot
    @State private var tab = 0
    @State private var confirmClear = false
    let onSaved: @MainActor (Bot)->Void
    let onStartChat: @MainActor ()->Void
    let clearDisabled: Bool
    let onClear: @MainActor (Bool) async -> Void
    init(bot:Bot,onSaved:@escaping @MainActor(Bot)->Void,onStartChat:@escaping @MainActor()->Void,clearDisabled:Bool,onClear:@escaping @MainActor(Bool) async->Void) {
        _profile=State(initialValue:bot);self.onSaved=onSaved;self.onStartChat=onStartChat;self.clearDisabled=clearDisabled;self.onClear=onClear
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing:24,pinnedViews:[.sectionHeaders]) {
                VStack(spacing:16) {
                    LiveBotAvatar(botID:profile.id,emoji:profile.avatar,color:profile.color,hasAvatar:profile.hasAvatar,updatedAt:profile.avatarUpdatedAt,size:96,appearance:profile.supportedAppearance)
                    VStack(spacing:8) {
                        Text(profile.name).font(.title2.bold())
                        if !profile.tags.isEmpty { Text(profile.tags.joined(separator:" · ")).font(.subheadline).foregroundStyle(.secondary) }
                        if !profile.persona.isEmpty { Text(profile.persona).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    }
                    Button("开始对话",systemImage:"bubble.left.and.bubble.right") { onStartChat() }.buttonStyle(.borderedProminent)
                }.padding(.horizontal,24).padding(.top,20)
                Section {
                    if tab==0 { overview.padding(.horizontal,16) }
                    else { LibraryView(scope:.bot(id:profile.id),initialKind:tab==1 ? "file":"image",embedded:true).id(tab) }
                } header: {
                    Picker("Bot 内容",selection:$tab) {
                        Text("概览").tag(0)
                        Text("文件 \(count(kind:"file"))").tag(1)
                        Text("图片 \(count(kind:"image"))").tag(2)
                    }.pickerStyle(.segmented).padding(.horizontal,16).padding(.vertical,10).background(Color.appBackground)
                }
            }.padding(.bottom,24)
        }
        .background(Color.appBackground)
        .navigationTitle(profile.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.topBarLeading) { DismissToolbarButton(kind:.close) {dismiss()} }
            ToolbarItem(placement:.topBarTrailing) {
                NavigationLink {
                    BotEditView(bot:profile,onSaved:{profile=$0;onSaved($0)})
                } label: { Image(systemName:"slider.horizontal.3") }.accessibilityLabel("编辑与权限")
            }
        }
        .confirmationDialog("清空对话？",isPresented:$confirmClear,titleVisibility:.visible) {
            Button("仅清空对话",role:.destructive) { Task {await onClear(false)} }
            Button("清空对话及该 Bot 的记忆",role:.destructive) { Task {await onClear(true)} }
        } message: { Text("资料库中的文件和图片会保留。清空后原消息定位将不可用。") }
    }
    private func count(kind:String)->Int { (app.libraryDownloads?.items ?? []).filter {$0.kind==kind && $0.botIDs.contains(profile.id)}.count }
    private var overview: some View {
        VStack(alignment:.leading,spacing:0) {
            NavigationLink { MemoryListView(botFilter:profile) } label: { overviewRow("记忆",icon:"brain") }
            Divider()
            NavigationLink { TaskListView(botID:profile.id,botName:profile.name) } label: { overviewRow("任务",icon:"checklist") }
            Divider()
            NavigationLink { RemindersView() } label: { overviewRow("全部提醒",icon:"alarm") }
            Divider()
            NavigationLink { DelegationLogView(bot:profile) } label: { overviewRow("协作记录",icon:"person.2") }
            Divider()
            Button(role:.destructive) { confirmClear=true } label: { overviewRow("清空对话",icon:"trash") }.disabled(clearDisabled)
        }.buttonStyle(.plain)
    }
    private func overviewRow(_ title:String,icon:String)->some View {
        HStack(spacing:12) {Image(systemName:icon).frame(width:24);Text(title);Spacer();Image(systemName:"chevron.right").font(.caption).foregroundStyle(.tertiary)}.padding(.vertical,18)
    }
}
