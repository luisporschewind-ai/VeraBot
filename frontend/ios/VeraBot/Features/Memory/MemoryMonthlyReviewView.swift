import SwiftUI
import VeraBotCore

struct MemoryMonthlyReviewView:View {
    @Environment(AppState.self) private var app
    @State private var review:MonthlyMemoryReview?
    @State private var errorText:String?
    @State private var loading=false
    private let month:String
    init(month:String=String(Calendar.current.dateComponents([.year,.month],from:Date()).year ?? 2026)+"-"+String(format:"%02d",Calendar.current.component(.month,from:Date()))) { self.month=month }
    var body:some View {
        ThemedList {
            if let errorText { Text(errorText).foregroundStyle(.red) }
            if loading && review == nil { ProgressView("正在整理本月回顾…") }
            if let review {
                Section("本月协助") { LabeledContent("完成的协助",value:"\(review.assistedCount) 次") }
                if !review.capabilities.isEmpty { Section("常用能力") { ForEach(review.capabilities.keys.sorted(),id:\.self) { key in LabeledContent(capabilityTitle(key),value:"\(review.capabilities[key] ?? 0) 次") } } }
                Section("新确认的记忆") {
                    if review.newMemories.isEmpty { Text("本月没有新增的普通记忆").foregroundStyle(.secondary) }
                    ForEach(review.newMemories) { m in NavigationLink { MemoryReviewMemoryDetail(memory:m).environment(app) } label:{ VStack(alignment:.leading){Text(m.content); Text(m.type.title).font(.caption).foregroundStyle(.secondary)} } }
                }
                Section("待确认") { LabeledContent("待确认候选",value:"\(review.candidateCount) 条") }
                if let suggestion=review.suggestion,!suggestion.isEmpty { Section("建议") { Text(suggestion) } }
                if review.reviewStatus == "pending" { Section { ProgressView("回顾生成中") } }
                if review.reviewStatus == "unavailable" { Section { Button("重试生成回顾") { Task { await load() } } } }
            }
        }
        .navigationTitle("\(month) 回顾")
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        loading=true; defer{loading=false}
        do { review=try await app.api.monthlyMemoryReview(month:month); errorText=nil }
        catch { errorText=app.message(for:error) }
    }
    private func capabilityTitle(_ key:String)->String { switch key {case "chat":return "对话";case "delegation":return "委派";case "memory":return "记忆整理";default:return key} }
}

private struct MemoryReviewMemoryDetail:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let memory:Memory
    @State private var errorText:String?
    var body:some View {
        ThemedForm {
            Section("记忆内容") { Text(memory.content) }
            Section("信息") { LabeledContent("类型",value:memory.type.title); LabeledContent("使用次数",value:"\(memory.useCount)") }
            if let errorText { Text(errorText).foregroundStyle(.red) }
            Section { Button("删除这条记忆",role:.destructive) { Task { do {_ = try await app.api.deleteMemory(id:memory.id); dismiss()} catch {errorText=app.message(for:error)} } } }
        }.navigationTitle("记忆详情")
    }
}
