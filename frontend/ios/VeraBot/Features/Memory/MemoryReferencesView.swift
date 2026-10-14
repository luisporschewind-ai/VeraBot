import SwiftUI
import VeraBotCore

struct MemoryReferencesView:View {
    @Environment(AppState.self) private var app
    let messageID:Int
    @State private var memories:[Memory]=[]
    @State private var notice: PageNotice?
    var body:some View {
        ThemedList {
            if let notice { PageConnectionNotice(notice: notice) { Task { await load() } }.connectionNoticeRow() }
            if memories.isEmpty && notice == nil { ContentUnavailableView("没有可显示的记忆",systemImage:"brain",description:Text("这条回答没有引用记忆，或相关记忆已删除或当前不可见。")) }
            ForEach(memories) { memory in VStack(alignment:.leading,spacing:5){Text(memory.content); Text("\(memory.type.title) · \(memory.scope == .global ? "共享资料" : "本 Bot")").font(.caption).foregroundStyle(.secondary)} }
        }
        .navigationTitle("回答参考的记忆")
        .task { await load() }
    }

    private func load() async {
        do { memories = try await app.api.memoryReferences(messageID: messageID).memories; notice = nil }
        catch { notice = .fromLoad(error, message: app.message(for: error)) }
    }
}
