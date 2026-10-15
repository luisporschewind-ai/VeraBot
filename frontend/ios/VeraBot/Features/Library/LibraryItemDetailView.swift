import SwiftUI
import QuickLook
import VeraBotCore

struct LibraryItemDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: VeraBotCore.LibraryItem
    @State private var preview: URL?
    @State private var sharing = false
    @State private var deleting = false
    @State private var wantsPreview = false
    @State private var error: String?
    var body: some View {
        let item=app.libraryDownloads?.items.first(where:{$0.id==self.item.id}) ?? self.item
        return List {
            Section {
                LibraryFileRow(item:item)
                if let url=app.libraryDownloads?.localURL(id:item.id) {
                    Button("打开原件",systemImage:"doc.viewfinder") { preview=url }
                    ShareLink(item:url) { Label("分享原件",systemImage:"square.and.arrow.up") }
                    Button("清除本机下载",systemImage:"arrow.down.circle") { app.libraryDownloads?.clearDownloaded(item:item) }
                    Text("清除下载会暂停自动下载，云端资料仍保留。").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(app.libraryDownloads?.active.contains(item.id) == true ? "正在下载…":"下载并打开原件",systemImage:"arrow.down.circle") {
                        wantsPreview=true
                        Task { _ = await app.libraryDownloads?.prepare(id:item.id,userInitiated:true);openWhenReady() }
                    }.disabled(item.availability != "available")
                    Text(item.availability == "available" ? "原件尚未下载；本次点击允许使用蜂窝网络。":"服务端原件不可用").font(.footnote).foregroundStyle(.secondary)
                }
                if item.kind=="file",item.textStatus != "ready" { Text("暂不能检索正文，仍可保存原件").font(.footnote).foregroundStyle(.secondary) }
                if let error=error ?? app.libraryDownloads?.errors[item.id] { Text(error).foregroundStyle(.secondary) }
            }
            Section("Bot 访问权限") {
                Text(item.botIDs.isEmpty ? "尚未关联 Bot":"已关联 \(item.botIDs.count) 个 Bot，可主动检索和读取此资料")
                Button("管理关联 Bot") { sharing=true }
            }
            Section("资料来源") {
                ForEach(Array(item.sources.enumerated()),id:\.offset) { _,source in
                    if source.messageAvailable {
                        NavigationLink { LibrarySourceConversationView(source:source) } label: {
                            VStack(alignment:.leading,spacing:4) {
                                Text(source.displayName)
                                Text("\(String(source.createdAt.prefix(10))) · 查看原消息").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        VStack(alignment:.leading,spacing:4) {
                            Text(source.displayName)
                            Text(source.kind=="upload" ? "直接上传":"原消息已清除").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section { Button("从资料库删除",role:.destructive) { deleting=true } }
        }
        .navigationTitle("资料详情").navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .task { await app.refreshLibrary();_ = await app.libraryDownloads?.prepare(id:item.id,userInitiated:false) }
        .onChange(of:app.libraryDownloads?.revision) { _,_ in openWhenReady() }
        .sheet(isPresented:$sharing) { NavigationStack { LibraryBotSharingSheet(item:item) { } } }
        .confirmationDialog("从资料库删除？",isPresented:$deleting,titleVisibility:.visible) {
            Button("删除资料及所有 Bot 关联",role:.destructive) {
                Task {
                    do {
                        try await app.libraryRepository?.delete(id:item.id)
                        await app.refreshLibrary();dismiss()
                    } catch { self.error=error.localizedDescription }
                }
            }
        } message: { Text("将影响 \(item.botIDs.count) 个 Bot。聊天中的文字保留，附件将不可用；离线设备将在下次联网同步后移除下载。") }
    }
    private func openWhenReady() { if wantsPreview,let url=app.libraryDownloads?.localURL(id:item.id) { preview=url;wantsPreview=false } }
}

private struct LibrarySourceConversationView: View {
    @Environment(AppState.self) private var app
    let source: LibrarySource
    @State private var bot: Bot?
    @State private var group: ChatGroup?
    @State private var loaded = false
    var body: some View {
        Group {
            if let bot { ChatView(bot:bot,api:app.api,repository:app.conversationRepository,highlightMessageID:source.messageID) }
            else if let group { GroupChatView(group:group,app:app,highlightMessageID:source.messageID) }
            else if loaded { ContentUnavailableView("来源暂不可用",systemImage:"bubble.left",description:Text("原消息可能已清除，或尚未同步到此设备。")) }
            else { ProgressView() }
        }.task {
            if let list=try? await app.conversationRepository?.cacheLists() {
                if source.kind=="private" { bot=list.bots.first {$0.id==source.botID} }
                if source.kind=="group" { group=list.groups.first {$0.id==source.sourceID} }
            }
            if bot==nil,source.kind=="private",let id=source.botID { bot=(try? await app.api.bots())?.bots.first(where:{$0.id==id}) }
            if group==nil,source.kind=="group",let id=source.sourceID { group=try? await app.groupAPI.group(id:id) }
            loaded=true
        }
    }
}
