import SwiftUI
import VeraBotCore

struct LibraryBotSharingSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: VeraBotCore.LibraryItem
    let onComplete: () -> Void
    @State private var bots: [Bot] = []
    @State private var selected = Set<Int>()
    @State private var original = Set<Int>()
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            Section { Text("选中的 Bot 可主动检索和读取这份资料；移除后撤销后续读取权限。既有回复不会被追溯删除。").font(.footnote) }
            ForEach(bots) { bot in
                Toggle(bot.name,isOn:Binding(get:{selected.contains(bot.id)},set:{if $0 {selected.insert(bot.id)} else {selected.remove(bot.id)}}))
            }
            if let error { Text(error).foregroundStyle(.secondary) }
        }.navigationTitle("关联 Bot")
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) }
            ToolbarItem(placement:.confirmationAction) { Button("保存") { confirming=true }.disabled(busy) }
        }
        .task {
            selected=Set(item.botIDs);original=selected
            if let list=try? await app.conversationRepository?.cacheLists() { bots=list.bots }
            if let fresh=try? await app.api.bots() { bots=fresh.bots }
        }
        .confirmationDialog("更新资料访问权限？",isPresented:$confirming,titleVisibility:.visible) {
            Button("确认更新") { Task { await save() } }
        } message: { Text("新增 \(selected.subtracting(original).count) 个 Bot 的访问权限，移除 \(original.subtracting(selected).count) 个 Bot 的访问权限。") }
        .interactiveDismissDisabled(busy)
    }
    private func save() async {
        guard let repo=app.libraryRepository else { return };busy=true;defer {busy=false}
        do {
            for id in original.subtracting(selected) { try await repo.unlink(id:item.id,botID:id);original.remove(id) }
            for id in selected.subtracting(original) { try await repo.link(id:item.id,botID:id);original.insert(id) }
            await app.refreshLibrary();onComplete();dismiss()
        } catch { self.error=error.localizedDescription }
    }
}

struct LibraryAddToBotSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let botID: Int
    let onComplete: () -> Void
    @State private var items: [VeraBotCore.LibraryItem] = []
    @State private var selected = Set<String>()
    @State private var confirming = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            Text("添加后，这个 Bot 可以主动检索和读取选中的资料。").font(.footnote)
            ForEach(items.filter {!$0.botIDs.contains(botID)}) { item in
                Button { if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) } } label: {
                    HStack { Text(item.name).foregroundStyle(.primary);Spacer();if selected.contains(item.id) {Image(systemName:"checkmark")} }
                }
            }
            if let error { Text(error).foregroundStyle(.secondary) }
        }.navigationTitle("从资料库添加")
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("关闭") {dismiss()}.disabled(busy) }
            ToolbarItem(placement:.confirmationAction) { Button("添加") {confirming=true}.disabled(selected.isEmpty || busy) }
        }
        .task { items=(try? await app.libraryRepository?.cachedItems()) ?? [] }
        .confirmationDialog("允许当前 Bot 读取这 \(selected.count) 份资料？",isPresented:$confirming,titleVisibility:.visible) {
            Button("关联并授权") {
                Task {
                    busy=true;defer {busy=false}
                    do { for id in selected {try await app.libraryRepository?.link(id:id,botID:botID)};onComplete();dismiss() }
                    catch {self.error=error.localizedDescription}
                }
            }
        }
    }
}
