import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct ReminderEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let reminder: Reminder?
    let bots: [Bot]
    let onSaved: () async -> Void

    @State private var title = ""
    @State private var note = ""
    @State private var hasDate = false
    @State private var hasTime = true
    @State private var date = Date()
    @State private var repeatPreset: ReminderRepeatPreset = .never
    @State private var priority = 0
    @State private var assignee: Int?
    @State private var errorText: String?
    @State private var conflict = false
    @State private var saving = false

    var body: some View {
        ThemedForm {
            Section {
                TextField("标题", text: $title)
                TextField("备注", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section {
                Toggle("日期", isOn: $hasDate)
                if hasDate {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                    Toggle("时间", isOn: $hasTime)
                    if hasTime {
                        DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
            }
            Section {
                Picker("重复", selection: $repeatPreset) {
                    ForEach(ReminderRepeatPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Picker("优先级", selection: $priority) {
                    Text("无").tag(0)
                    Text("低").tag(1)
                    Text("中").tag(2)
                    Text("高").tag(3)
                }
                Picker("归属 Bot", selection: $assignee) {
                    Text("无").tag(Optional<Int>.none)
                    ForEach(bots) { bot in
                        Text(bot.name).tag(Optional(bot.id))
                    }
                }
            } footer: {
                Text("归属的 Bot 可以查看和管理这条提醒。")
            }
            if let reminder, reminder.createdBy == "bot" {
                Section("来源") {
                    Text(reminder.sourceName.isEmpty ? "已删除的 Bot" : "由「\(reminder.sourceName)」在对话中创建")
                    if let messageID = reminder.sourceMessageId, let botID = reminder.sourceBotId {
                        Button("查看对话") {
                            Task { await app.open(link: "bot/\(botID)/chat?message=\(messageID)") }
                        }
                    }
                }
            }
            if reminder != nil {
                Section {
                    Button("删除提醒", role: .destructive) { Task { await remove() } }
                }
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .navigationTitle(reminder == nil ? "新建提醒" : "编辑提醒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DismissToolbarButton { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }.disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("这条提醒已在别处修改", isPresented: $conflict) {
            Button("好") { Task { await reload() } }
        }
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let reminder else { return }
        title = reminder.title
        note = reminder.note ?? ""
        hasDate = reminder.dueUTC != nil || reminder.dueAt != nil
        hasTime = !reminder.allDay && hasDate
        date = reminder.scheduleDate ?? Date()
        repeatPreset = ReminderRepeatPreset.matching(reminder.rrule)
        priority = reminder.priority
        assignee = reminder.assigneeBotId
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let body = ReminderWrite(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                 note: note.isEmpty ? nil : note,
                                 dueAt: hasDate ? iso(date) : nil,
                                 clearDue: reminder != nil && !hasDate,
                                 timeZone: TimeZone.current.identifier,
                                 allDay: hasDate ? !hasTime : nil,
                                 rrule: hasDate ? repeatPreset.rrule(on: date) : nil,
                                 clearRrule: reminder?.rrule != nil && (!hasDate || repeatPreset == .never),
                                 priority: priority,
                                 assigneeBotId: assignee,
                                 clearAssignee: reminder != nil && assignee == nil,
                                 notify: hasDate,
                                 expectedVersion: reminder?.version)
        do {
            if let reminder {
                _ = try await app.api.updateReminder(id: reminder.id, body)
            } else {
                _ = try await app.api.createReminder(body)
            }
            await onSaved()
            dismiss()
        } catch let error as APIError where error.status == 409 && error.code == "version_conflict" {
            conflict = true
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func reload() async {
        guard let reminder else { return }
        if let fresh = try? await app.api.reminder(id: reminder.id) {
            title = fresh.title
            note = fresh.note ?? ""
        }
        await onSaved()
    }

    private func remove() async {
        guard let reminder else { return }
        _ = try? await app.api.deleteReminder(reminder.id, scope: "series")
        await onSaved()
        dismiss()
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
