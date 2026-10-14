import SwiftUI
import VeraBotCore

struct ReminderDetailView: View {
    let reminder: Reminder
    let bots: [Bot]
    var changed: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var editing = false
    var body: some View {
        ThemedForm {
            Section {
                Text(reminder.title).font(.headline)
                if let due = reminder.scheduleDate {
                    LabeledContent("时间", value: due.formatted(date: .abbreviated, time: .shortened))
                }
                if let repeatLabel = reminder.repeatLabel { LabeledContent("重复", value: repeatLabel) }
                if let note = reminder.note, !note.isEmpty { Text(note) }
                LabeledContent("来源", value: reminder.sourceName)
                if let botID = reminder.sourceBotId {
                    Button("查看对话") {
                        let query = reminder.sourceMessageId.map { "?message=\($0)" } ?? ""
                        dismiss()
                        Task { await app.open(link: "bot/\(botID)/chat\(query)") }
                    }
                }
            }
            Section { Button("编辑提醒") { editing = true } }
        }
        .navigationTitle("提醒详情").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(isPresented: $editing) {
            NavigationStack { ReminderEditorView(reminder: reminder, bots: bots, onSaved: changed) }
        }
    }
}
