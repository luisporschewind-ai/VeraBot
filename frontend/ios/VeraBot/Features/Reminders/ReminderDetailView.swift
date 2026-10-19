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
    @State private var taskAnswer = ""
    @State private var taskBusy = false
    @State private var confirmTaskStop = false
    @FocusState private var answerFocused: Bool

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
                        HStack {
                            Text("状态").foregroundStyle(.secondary)
                            Spacer()
                            Text(task.status)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                        if let next = task.nextRun {
                            LabeledContent("下次执行", value: next.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let summary = task.lastResultSummary, !summary.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("最近结果").font(.caption).foregroundStyle(.secondary)
                                Text(summary).font(.subheadline)
                            }
                            if let botID = task.botId ?? item.reminder.assigneeBotId {
                                Button("查看全文") {
                                    let query = task.messageId.map { "?message=\($0)" } ?? ""
                                    dismiss()
                                    Task { await app.open(link: "bot/\(botID)/chat\(query)") }
                                }
                            }
                        }
                        if !task.history.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("执行记录").font(.caption).foregroundStyle(.secondary)
                                ForEach(Array(task.history.enumerated()), id: \.offset) { _, entry in
                                    HStack {
                                        Image(systemName: entry.ok ? "checkmark.circle" : "xmark.circle")
                                            .foregroundStyle(entry.ok ? .green : .red)
                                        Text(entry.at?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                            .font(.caption)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        if task.needsUser, task.kind == "owned" {
                            if let question = task.waitQuestion, !question.isEmpty {
                                Text(question).font(.subheadline)
                            }
                            if let actionID = task.waitActionId {
                                NavigationLink("查看并确认操作") {
                                    TaskApprovalView(actionID: actionID, onResolved: { Task { await load() } })
                                }
                            } else {
                                TextField("补充材料或下一步安排", text: $taskAnswer, axis: .vertical)
                                    .focused($answerFocused)
                                Button("回复并继续") { Task { await answerTask(task.id) } }
                                    .disabled(taskBusy || taskAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        // 任务操作（不暴露内部字段）
                        HStack(spacing: 12) {
                            if task.kind == "scheduled" {
                                Button(task.statusKey == "pending" ? "暂停" : "继续") {
                                    Task { await actTask(task.id, task.statusKey == "pending" ? "pause" : "resume") }
                                }
                                Button("立即执行") { Task { await actTask(task.id, "run") } }
                            } else if task.kind == "owned" {
                                if task.statusKey == "needs_user" || task.statusKey == "failed" {
                                    Button("继续") { Task { await actTask(task.id, "continue") } }
                                }
                                if task.statusKey != "done" {
                                    Button("停止", role: .destructive) { confirmTaskStop = true }
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(taskBusy)
                        .confirmationDialog("停止这项任务？", isPresented: $confirmTaskStop, titleVisibility: .visible) {
                            Button("停止任务", role: .destructive) {
                                if let task = item.task { Task { await actTask(task.id, "stop") } }
                            }
                            Button("取消", role: .cancel) {}
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
            if item?.hasTask == true {
                Button("删除并停止 Bot 任务", role: .destructive) { Task { await remove(scope: "series", stopTask: true) } }
                Button("仅删除事项") { Task { await remove(scope: "series", stopTask: false) } }
            } else if item?.reminder.rrule != nil {
                Button("仅删除这一次") { Task { await remove(scope: "occurrence", stopTask: false) } }
                Button("删除整个系列", role: .destructive) { Task { await remove(scope: "series", stopTask: false) } }
            } else {
                Button("删除", role: .destructive) { Task { await remove(scope: "series", stopTask: false) } }
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
            if app.pendingItemFocusTask {
                app.pendingItemFocusTask = false
                answerFocused = true
            }
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

    private func answerTask(_ taskID: Int) async {
        taskBusy = true
        defer { taskBusy = false }
        do {
            item = try await app.api.itemTaskAction(id: itemID, action: "input", message: taskAnswer)
            taskAnswer = ""
            await changed()
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func actTask(_ taskID: Int, _ action: String) async {
        taskBusy = true
        defer { taskBusy = false }
        do {
            item = try await app.api.itemTaskAction(id: itemID, action: action)
            await changed()
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func remove(scope: String, stopTask: Bool) async {
        do {
            _ = try await app.api.deleteItem(itemID, scope: scope, stopTask: stopTask)
        } catch {
            _ = try? await app.api.deleteReminder(itemID, scope: scope)
        }
        pendingDelete = false
        await changed()
        dismiss()
    }
}
