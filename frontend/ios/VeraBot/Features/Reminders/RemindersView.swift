import SwiftUI
import VeraBotCore

struct RemindersView: View {
    @Environment(AppState.self) private var app
    @State private var reminders: [Reminder] = []
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(reminders) { r in
                    HStack {
                        Image(systemName: r.done == 1 ? "checkmark.circle.fill" : "alarm")
                            .foregroundStyle(r.done == 1 ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.content).strikethrough(r.done == 1)
                            Text("\(formatted(r.dueAt)) · 来自 \(r.botName ?? "已删除的 Bot")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        if r.done == 0 {
                            Button("完成") { Task { await complete(r) } }.tint(.green)
                        }
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(.red) }
            }
            .overlay {
                if reminders.isEmpty && errorText == nil {
                    ContentUnavailableView("暂无提醒", systemImage: "alarm",
                                           description: Text("在对话里说「提醒我…」即可创建"))
                }
            }
            .navigationTitle("提醒事项")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func formatted(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "未设时间" }
        return String(s.replacingOccurrences(of: "T", with: " ").prefix(16))
    }

    private func load() async {
        do {
            reminders = try await app.api.reminders().reminders
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func complete(_ r: Reminder) async {
        _ = try? await app.api.completeReminder(r.id)
        await load()
    }
}
