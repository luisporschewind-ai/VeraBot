import SwiftUI
import VeraBotCore
import VeraBotNetworking

/// 先看后改：只读详情；清单可勾选；右上编辑；底部红色删除。
struct ReminderDetailView: View {
    let itemID: Int
    let bots: [Bot]
    var changed: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app
    @State private var item: Item?
    @State private var editing = false
    @State private var pendingDelete = false
    @State private var ownedTask: OwnedTask?
    @State private var errorText: String?

    var body: some View {
        ThemedForm {
            if let item {
                Section {
                    Text(item.title).font(.headline)
                    if item.reminder.scheduleDate != nil {
                        LabeledContent("时间", value: ReminderTimeText.when(item.reminder))
                    } else {
                        LabeledContent("时间", value: "待办（无日期）")
                    }
                    if let repeatLabel = item.reminder.repeatLabel {
                        LabeledContent("重复", value: repeatLabel)
                    }
                    LabeledContent("通知", value: item.reminder.notify ? "开" : "关")
                    if let note = item.reminder.note, !note.isEmpty { Text(note) }
                }
                if !item.checklist.isEmpty {
                    Section("清单") {
                        ForEach(item.checklist) { entry in
                            Button {
                                Task { await toggle(entry) }
                            } label: {
                                HStack {
                                    Image(systemName: entry.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(entry.done ? Color.accentColor : Color.secondary)
                                    Text(entry.text).strikethrough(entry.done)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let source = sourceLine(item) {
                    Section("来源") {
                        if let botID = item.reminder.sourceBotId {
                            Button(source) {
                                let query = item.reminder.sourceMessageId.map { "?message=\($0)" } ?? ""
                                dismiss()
                                Task { await app.open(link: "bot/\(botID)/chat\(query)") }
                            }
                        } else {
                            Text(source)
                        }
                    }
                }
                if let task = item.task {
                    Section("Bot 任务") {
                        LabeledContent("状态", value: task.status)
                        if let next = task.nextRun {
                            LabeledContent("下次执行", value: next.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let summary = task.lastResultSummary, !summary.isEmpty {
                            Text(summary).font(.subheadline)
                        }
                        if let botID = task.botId ?? item.reminder.assigneeBotId {
                            Button("查看对话") {
                                let query = task.messageId.map { "?message=\($0)" } ?? ""
                                dismiss()
                                Task { await app.open(link: "bot/\(botID)/chat\(query)") }
                            }
                        }
                        if task.needsUser, task.kind == "owned" {
                            Button("去处理") { Task { await openOwned(task.id) } }
                        }
                    }
                }
                Section {
                    Button("删除", role: .destructive) { pendingDelete = true }
                }
            } else if let errorText {
                Section { Text(errorText).foregroundStyle(.secondary) }
            } else {
                Section { ProgressView() }
            }
        }
        .navigationTitle("安排详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if item != nil { Button("编辑") { editing = true } }
            }
        }
        .task { await load() }
        .sheet(isPresented: $editing) {
            if let item {
                NavigationStack {
                    ReminderEditorView(reminder: item.reminder, bots: bots, checklistSeed: item.checklist) {
                        await load()
                        await changed()
                    }
                }
            }
        }
        .sheet(item: $ownedTask) { task in
            NavigationStack { TaskDetailView(initial: task) }
        }
        .confirmationDialog("删除这条安排？", isPresented: $pendingDelete, titleVisibility: .visible) {
            if item?.reminder.rrule != nil {
                Button("仅删除这一次") { Task { await remove(scope: "occurrence") } }
                Button("删除整个系列", role: .destructive) { Task { await remove(scope: "series") } }
            } else {
                Button("删除", role: .destructive) { Task { await remove(scope: "series") } }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func sourceLine(_ item: Item) -> String? {
        if item.reminder.createdBy == "bot" || item.reminder.sourceBotId != nil {
            let name = item.reminder.botName ?? item.reminder.sourceName
            return "来自 与 \(name) 的对话"
        }
        return nil
    }

    private func load() async {
        do {
            item = try await app.api.item(id: itemID)
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func toggle(_ entry: ChecklistEntry) async {
        do {
            item = try await app.api.toggleChecklist(id: itemID, checklistID: entry.id, done: !entry.done)
            await changed()
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func openOwned(_ taskID: Int) async {
        do {
            ownedTask = try await app.api.ownedTask(taskID)
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func remove(scope: String) async {
        _ = try? await app.api.deleteReminder(itemID, scope: scope)
        pendingDelete = false
        await changed()
        dismiss()
    }
}
