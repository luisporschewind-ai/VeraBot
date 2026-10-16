import SwiftUI
import VeraBotCore
import VeraBotData

struct LibraryView: View {
    @Environment(AppState.self) private var app
    let scope: LibraryScope
    var initialKind = "file"
    var embedded = false
    @State private var vm: LibraryViewModel?
    @State private var kind = "file"
    @State private var query = ""
    @State private var onlyDownloaded = false
    @State private var botFilter: Int?
    @State private var upload = false
    @State private var addExisting = false
    @State private var confirmDownload = false
    @State private var remoteMatches: [VeraBotCore.LibraryItem]?
    @State private var searchedQuery = ""
    private var botID: Int? { if case .bot(let id)=scope { return id };return nil }
    private var isGroup: Bool { if case .group = scope { return true }; return false }
    private var visible: [VeraBotCore.LibraryItem] {
        var list=vm?.visibleItems(kind:kind,query:query) ?? []
        if !query.isEmpty,searchedQuery==query,let remoteMatches { list=remoteMatches.filter {$0.kind==kind && scope.contains($0)} }
        if let botFilter { list=list.filter {$0.botIDs.contains(botFilter)} }
        if onlyDownloaded { list=list.filter {app.libraryDownloads?.localURL(id:$0.id) != nil} }
        return list
    }
    var body: some View {
        Group {
            if embedded { content }
            else { ScrollView { content.padding(.vertical) }.navigationTitle("资料库") }
        }
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text:$query,prompt:"搜索名称或正文")
        .toolbar {
            if !isGroup {
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    Button("上传文件或图片",systemImage:"plus") { upload=true }
                    if botID != nil { Button("从资料库添加",systemImage:"folder") { addExisting=true } }
                    Toggle("仅显示已下载",isOn:$onlyDownloaded)
                    Menu("筛选来源 Bot") {
                        Button("全部") { botFilter=nil }
                        ForEach(Array(Set((vm?.items ?? []).flatMap(\.botIDs))).sorted(),id:\.self) { id in
                            Button(sourceName(id)) { botFilter=id }
                        }
                    }
                    Button("下载全部原件",systemImage:"arrow.down.circle") { confirmDownload=true }
                    if let downloads=app.libraryDownloads {
                        Button(downloads.paused ? "恢复 Wi-Fi 自动下载":"暂停自动下载") { downloads.paused.toggle() }
                    }
                } label: { Image(systemName:"ellipsis.circle") }
                .accessibilityLabel("资料管理")
            }
            }
        }
        .task {
            kind=initialKind
            guard let repo=app.libraryRepository else { return }
            vm=LibraryViewModel(repository:repo,scope:scope)
            await reload()
        }
        .task(id:query) {
            remoteMatches=nil
            guard !query.isEmpty else { return }
            do { try await Task.sleep(for:.milliseconds(400)) } catch { return }
            let text=query;let result=await vm?.search(query:text)
            guard !Task.isCancelled,text==query else { return }
            remoteMatches=result;searchedQuery=text
        }
        .refreshable { await reload() }
        .onAppear { if vm != nil { Task { await reload() } } }
        .onChange(of:app.libraryDownloads?.items) { _,_ in Task {await vm?.refreshCached()} }
        .sheet(isPresented:$upload) { NavigationStack { LibraryUploadSheet(botID:botID) { Task { await reload() } } } }
        .sheet(isPresented:$addExisting) { if let botID { NavigationStack { LibraryAddToBotSheet(botID:botID) { Task { await reload() } } } } }
        .confirmationDialog("下载全部原件？",isPresented:$confirmDownload,titleVisibility:.visible) {
            Button("下载原件") { if let downloads=app.libraryDownloads { downloads.enqueue(items:vm?.items ?? [],mode:.manualCellularAllowed) } }
        } message: { Text("预计还需下载 \(ByteCountFormatter.string(fromByteCount:app.libraryDownloads?.remainingBytes ?? 0,countStyle:.file))，本次允许使用蜂窝网络。") }
    }
    private var content: some View {
        VStack(spacing:16) {
            if !embedded {
                Picker("资料类型",selection:$kind) {
                    Text("文件 \(vm?.visibleItems(kind:"file",query:"").count ?? 0)").tag("file")
                    Text("图片 \(vm?.visibleItems(kind:"image",query:"").count ?? 0)").tag("image")
                }.pickerStyle(.segmented)
            }
            if let error=vm?.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if visible.isEmpty {
                if vm?.loading == true { ProgressView() }
                else {
                    BotNoticeCard(notice: BotNotice(
                        title: query.isEmpty ? "暂无资料" : "没有找到资料",
                        detail: query.isEmpty
                            ? (isGroup ? "本群聊天中的文件和图片会显示在这里。" : "聊天中的文件和图片会自动归集，也可以直接上传。")
                            : "试试其他关键词。"
                    ))
                }
            } else if kind=="image" { LibraryImageGrid(items:visible) }
            else { LibraryFileList(items:visible,botID:botID) }
        }.padding(.horizontal,16)
    }
    private func sourceName(_ id: Int) -> String {
        (vm?.items ?? []).flatMap(\.sources).first(where:{$0.botID==id})?.displayName ?? "Bot \(id)"
    }
    private func reload() async {
        await vm?.load()
        if let vm { app.libraryDownloads?.updateCatalog(vm.items,complete:vm.directorySynced) }
    }
}
