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
    @State private var selectedDay = Date()
    @State private var selectedTime = Date()
    @State private var repeatPreset: ReminderRepeatPreset = .never
    @State private var priority = 0
    @State private var assignee: Int?
    @State private var expectedVersion: Int?
    @State private var loadedReminder: Reminder?
    @State private var errorText: String?
    @State private var conflict = false
    @State private var confirmDelete = false
    @State private var saving = false
    @State private var initialized = false
    @State private var scheduleChanged = false
    @State private var repeatChanged = false
    @State private var timeSelectionChanged = false

    private var editorTimeZone: TimeZone {
        TimeZone(identifier: loadedReminder?.timeZone ?? reminder?.timeZone ?? TimeZone.current.identifier) ?? .current
    }

    private var editorCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = editorTimeZone
        return calendar
    }

    private var hasDateBinding: Binding<Bool> {
        Binding(get: { hasDate }, set: { setHasDate($0) })
    }

    private var hasTimeBinding: Binding<Bool> {
        Binding(get: { hasTime }, set: { setHasTime($0) })
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { selectedDay }, set: {
            selectedDay = $0
            scheduleChanged = true
        })
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { selectedTime }, set: {
            selectedTime = $0
            scheduleChanged = true
            timeSelectionChanged = true
        })
    }

    private var repeatBinding: Binding<ReminderRepeatPreset> {
        Binding(get: { repeatPreset }, set: {
            guard $0 != repeatPreset else { return }
            repeatPreset = $0
            repeatChanged = true
        })
    }

    private var repeatOptions: [ReminderRepeatPreset] {
        let presets = ReminderRepeatPreset.allCases.filter { $0 != .custom }
        return repeatPreset == .custom ? presets + [.custom] : presets
    }

    var body: some View {
        ThemedForm {
            Section {
                TextField("标题", text: $title)
                TextField("备注", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section {
                CompactToggle(isOn: hasDateBinding) {
                    Button("日期") { setHasDate(!hasDate) }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                if hasDate {
                    DatePicker("日期", selection: dayBinding, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("提醒日期")
                        .environment(\.timeZone, editorTimeZone)
                    CompactToggle(isOn: hasTimeBinding) {
                        Button("时间") { setHasTime(!hasTime) }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    if hasTime {
                        DatePicker("时间", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .accessibilityLabel("提醒时间")
                            .environment(\.timeZone, editorTimeZone)
                    }
                }
            }
            Section {
                Picker("重复", selection: repeatBinding) {
                    ForEach(repeatOptions) { preset in
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
                    Button("删除提醒", role: .destructive) { confirmDelete = true }
                        .disabled(saving)
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
                Button("保存") { Task { await save() } }
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("这条提醒已在别处修改", isPresented: $conflict) {
            Button("重新加载") { Task { await reload() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("重新加载会用最新内容替换当前编辑内容。")
        }
        .confirmationDialog(loadedReminder?.rrule == nil ? "删除提醒" : "删除重复提醒",
                            isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            if loadedReminder?.rrule != nil {
                Button("仅删除这一次") { Task { await remove(scope: "occurrence") } }
                Button("删除整个系列", role: .destructive) { Task { await remove(scope: "series") } }
            } else {
                Button("删除", role: .destructive) { Task { await remove(scope: "series") } }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            if !initialized { fill(from: reminder) }
        }
    }

    private func setHasDate(_ enabled: Bool) {
        guard enabled != hasDate else { return }
        hasDate = enabled
        scheduleChanged = true
        guard enabled else { return }

        let wasUndated = loadedReminder.map { $0.dueUTC == nil && $0.dueAt == nil } ?? true
        if wasUndated {
            let initial = Date().addingTimeInterval(120)
            selectedDay = initial
            selectedTime = initial
            hasTime = true
            timeSelectionChanged = false
        }
    }

    private func setHasTime(_ enabled: Bool) {
        guard enabled != hasTime else { return }
        hasTime = enabled
        scheduleChanged = true
    }

    private func fill(from reminder: Reminder?) {
        loadedReminder = reminder
        if let reminder {
            title = reminder.title
            note = reminder.note ?? ""
            hasDate = reminder.dueUTC != nil || reminder.dueAt != nil
            hasTime = !reminder.allDay
            let originalDate = reminder.dueUTC ?? VeraBotDate.parse(reminder.dueAt) ?? Date()
            selectedDay = originalDate
            selectedTime = originalDate
            repeatPreset = ReminderRepeatPreset.matching(reminder.rrule)
            priority = reminder.priority
            assignee = reminder.assigneeBotId
            expectedVersion = reminder.version
        } else {
            let now = Date()
            title = ""
            note = ""
            hasDate = false
            hasTime = true
            selectedDay = now
            selectedTime = now
            repeatPreset = .never
            priority = 0
            assignee = nil
            expectedVersion = nil
        }
        scheduleChanged = false
        repeatChanged = false
        timeSelectionChanged = false
        errorText = nil
        initialized = true
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }

        let scheduleDate: Date?
        if hasDate && scheduleChanged {
            guard let value = selectedDateForSave() else {
                errorText = "日期和时间无效，请重新选择。"
                return
            }
            scheduleDate = value
        } else {
            scheduleDate = nil
        }

        let existingRule = loadedReminder?.rrule
        let clearRule = existingRule != nil && ((!hasDate && scheduleChanged) || (repeatChanged && repeatPreset == .never))
        let updateRule = repeatChanged
            || (scheduleChanged && existingRule != nil && repeatPreset != .custom && hasDate)
            || (reminder == nil && hasDate && repeatPreset != .never)
        let rule = updateRule && hasDate && repeatPreset != .custom && repeatPreset != .never
            ? repeatPreset.rrule(on: scheduleDate ?? combinedSelectionDate(), calendar: editorCalendar)
            : nil
        let noteChanged = loadedReminder.map { note != ($0.note ?? "") } ?? !note.isEmpty
        let body = ReminderWrite(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                 note: noteChanged ? note : nil,
                                 dueAt: scheduleDate.map(VeraBotDate.format),
                                 clearDue: loadedReminder != nil && scheduleChanged && !hasDate,
                                 timeZone: scheduleChanged ? editorTimeZone.identifier : nil,
                                 allDay: scheduleChanged ? (hasDate && !hasTime) : nil,
                                 rrule: rule,
                                 clearRrule: clearRule,
                                 priority: priority,
                                 assigneeBotId: assignee,
                                 clearAssignee: loadedReminder != nil && assignee == nil,
                                 notify: scheduleChanged ? hasDate : nil,
                                 expectedVersion: reminder == nil ? nil : expectedVersion,
                                 clearNote: loadedReminder != nil && noteChanged && note.isEmpty)
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

    private func selectedDateForSave() -> Date? {
        var time = selectedTime
        let wasUndated = loadedReminder.map { $0.dueUTC == nil && $0.dueAt == nil } ?? true
        if wasUndated && !timeSelectionChanged && editorCalendar.isDateInToday(selectedDay) {
            time = Date().addingTimeInterval(120)
        }
        return combinedSelectionDate(day: selectedDay, time: time)
    }

    private func combinedSelectionDate(day: Date? = nil, time: Date? = nil) -> Date? {
        let timeParts = editorCalendar.dateComponents([.hour, .minute], from: time ?? selectedTime)
        guard let hour = timeParts.hour, let minute = timeParts.minute else { return nil }
        return editorCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: day ?? selectedDay,
                                  matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    private func reload() async {
        guard let reminder else { return }
        do {
            let fresh = try await app.api.reminder(id: reminder.id)
            fill(from: fresh)
            await onSaved()
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func remove(scope: String) async {
        guard let reminder, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await app.api.deleteReminder(reminder.id, scope: scope)
            await onSaved()
            dismiss()
        } catch {
            errorText = app.message(for: error)
        }
    }
}
