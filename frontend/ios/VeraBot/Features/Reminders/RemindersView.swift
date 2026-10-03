import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct RemindersView: View {
    @Environment(AppState.self) private var app
    @State private var segment = 0
    @State private var reminders: [Reminder] = []
    @State private var bots: [Bot] = []
    @State private var filter: ReminderListFilter = .all
    @State private var showDone = false
    @State private var errorText: String?
    @State private var editing: Reminder?
    @State private var creating = false
    @State private var completedCount = 0
    @State private var pendingDelete: Reminder?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("提醒或通知", selection: $segment) {
                    Text("提醒").tag(0)
                    Text("通知").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                if segment == 0 {
                    reminderList
                } else {
                    InboxView()
                }
            }
            .navigationTitle("提醒")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    if segment == 0 {
                        Button { creating = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("新建提醒")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                NavigationStack {
                    ReminderEditorView(reminder: nil, bots: bots) { await load() }
                }
            }
            .sheet(item: $editing) { item in
                NavigationStack {
                    ReminderEditorView(reminder: item, bots: bots) { await load() }
                }
            }
            .confirmationDialog("删除重复提醒", isPresented: Binding(get: { pendingDelete != nil },
                                                                  set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { item in
                if item.rrule != nil {
                    Button("仅删除这一次") { Task { await remove(item, scope: "occurrence") } }
                    Button("删除整个系列", role: .destructive) { Task { await remove(item, scope: "series") } }
                } else {
                    Button("删除", role: .destructive) { Task { await remove(item, scope: "series") } }
                }
                Button("取消", role: .cancel) {}
            }
            .hapticFeedback(.success, trigger: completedCount)
            .task { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .verabotRemindersChanged)) { _ in
                Task { await load() }
            }
            .onChange(of: app.pendingLink) { _, link in
                apply(link)
            }
        }
    }

    private var reminderList: some View {
        ThemedList {
            let sections = ReminderGrouping.sections(reminders, filter: filter, showDone: showDone)
            ForEach(sections, id: \.0) { bucket, rows in
                Section(bucket.title) {
                    ForEach(rows) { item in
                        Button { editing = item } label: { ReminderRow(item: item) }
                            .swipeActions(edge: .trailing) {
                                if item.status != .done {
                                    Button("完成") { Task { await complete(item) } }.tint(.green)
                                }
                                Button("删除", role: .destructive) { pendingDelete = item }
                            }
                            .swipeActions(edge: .leading) {
                                if item.status != .done && item.status != .cancelled {
                                    snoozeMenu(item)
                                }
                            }
                            .contextMenu {
                                Button("编辑") { editing = item }
                                if item.status != .done { Button("完成") { Task { await complete(item) } } }
                                Button("删除", role: .destructive) { pendingDelete = item }
                            }
                    }
                }
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .overlay {
            if reminders.isEmpty && errorText == nil {
                ContentUnavailableView {
                    Label("暂无提醒", systemImage: "alarm")
                } description: {
                    Text("在对话里说「提醒我…」，或点右上角新建")
                } actions: {
                    Button("新建提醒") { creating = true }
                }
            }
        }
        .refreshable { await load() }
    }

    private var filterMenu: some View {
        Menu {
            Button("全部") { filter = .all }
            Button("我创建的") { filter = .createdByUser }
            Button("Bot 创建的") { filter = .createdByBot }
            if !bots.isEmpty {
                Menu("按 Bot") {
                    ForEach(bots) { bot in
                        Button(bot.name) { filter = .bot(bot.id) }
                    }
                }
            }
            Toggle("显示已完成", isOn: $showDone)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("筛选")
    }

    private func snoozeMenu(_ item: Reminder) -> some View {
        Menu("稍后") {
            ForEach(SnoozeChoice.allCases) { choice in
                Button(choice.title) { Task { await snooze(item, choice) } }
            }
        }
    }

    private func load() async {
        do {
            async let list = app.api.reminders()
            async let botList = app.api.bots()
            reminders = try await list.reminders
            bots = try await botList.bots
            errorText = nil
            apply(app.pendingLink)
            await app.syncReminders()
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func complete(_ item: Reminder) async {
        if (try? await app.api.completeReminder(item.id, idempotencyKey: nil)) != nil {
            completedCount += 1
        }
        await load()
    }

    private func snooze(_ item: Reminder, _ choice: SnoozeChoice) async {
        let until = choice.until()?.ISO8601Format()
        _ = try? await app.api.snoozeReminder(item.id, minutes: choice.minutes(), until: until, idempotencyKey: nil)
        await load()
    }

    private func remove(_ item: Reminder, scope: String) async {
        _ = try? await app.api.deleteReminder(item.id, scope: scope)
        pendingDelete = nil
        await load()
    }

    private func apply(_ link: DeepLink?) {
        guard let link else { return }
        switch link {
        case .reminder(let id):
            segment = 0
            editing = reminders.first { $0.id == id }
            if editing == nil, !reminders.isEmpty { app.missingNotice = "内容已不存在" }
        case .reminders(let bucket):
            segment = 0
            if bucket == "due" { filter = .all }
        case .inbox:
            segment = 1
        default:
            return
        }
        app.pendingLink = nil
    }
}

private struct ReminderRow: View {
    let item: Reminder

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.done == 1 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.status == .due ? .red : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title).strikethrough(item.done == 1)
                    if item.priority >= 2 {
                        Image(systemName: "exclamationmark")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }
                Text(ReminderTimeText.subtitle(item))
                    .font(.caption)
                    .foregroundStyle(item.status == .due ? .red : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
