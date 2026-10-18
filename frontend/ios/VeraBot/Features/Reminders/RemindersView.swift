import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct RemindersView: View {
    @Environment(AppState.self) private var app
    @State private var segment = 0
    @State private var items: [Item] = []
    @State private var bots: [Bot] = []
    @State private var filter: ItemListFilter = .all
    @State private var showDone = false
    @State private var notice: PageNotice?
    @State private var viewingID: Int?
    @State private var creating = false
    @State private var completedCount = 0
    @State private var pendingDelete: Item?

    var body: some View {
        NavigationStack {
            Group {
                if segment == 0 {
                    itemList
                } else {
                    InboxView(header: AnyView(segmentPicker))
                }
            }
            .navigationTitle("安排")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    if segment == 0 {
                        Button { creating = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("新建安排")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                NavigationStack {
                    ReminderEditorView(reminder: nil, bots: bots) { await load() }
                }
            }
            .sheet(isPresented: Binding(get: { viewingID != nil }, set: { if !$0 { viewingID = nil } })) {
                if let viewingID {
                    NavigationStack {
                        ReminderDetailView(itemID: viewingID, bots: bots) { await load() }
                    }
                }
            }
            .confirmationDialog("删除重复安排", isPresented: Binding(get: { pendingDelete != nil },
                                                                  set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { item in
                if item.reminder.rrule != nil {
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
            .onChange(of: app.pendingAgendaBotID) { _, botID in
                if let botID {
                    filter = .bot(botID)
                    segment = 0
                    app.pendingAgendaBotID = nil
                }
            }
        }
    }

    private var segmentPicker: some View {
        Picker("提醒或通知", selection: $segment) {
            Text("提醒").tag(0)
            Text("通知").tag(1)
        }
        .pickerStyle(.segmented)
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private var itemList: some View {
        ThemedList {
            Section { } header: { segmentPicker }
            if let notice {
                PageConnectionNotice(notice: notice) { Task { await load() } }
                    .connectionNoticeRow()
            }
            let sections = ItemGrouping.sections(items, filter: filter, showDone: showDone)
            ForEach(sections, id: \.0) { bucket, rows in
                Section(bucket.title) {
                    ForEach(rows) { item in
                        Button { viewingID = item.id } label: { AgendaRow(item: item) }
                            .swipeActions(edge: .trailing) {
                                if item.reminder.status != .done {
                                    Button("完成") { Task { await complete(item) } }.tint(.green)
                                }
                                Button("删除", role: .destructive) { pendingDelete = item }
                            }
                            .swipeActions(edge: .leading) {
                                if item.reminder.status != .done && item.reminder.status != .cancelled {
                                    snoozeMenu(item)
                                }
                            }
                            .contextMenu {
                                Button("查看") { viewingID = item.id }
                                if item.reminder.status != .done { Button("完成") { Task { await complete(item) } } }
                                Button("删除", role: .destructive) { pendingDelete = item }
                            }
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty && notice == nil {
                ContentUnavailableView {
                    Label("暂无安排", systemImage: "alarm")
                } description: {
                    Text("在对话里说「提醒我…」，或点右上角新建")
                } actions: {
                    Button("新建安排") { creating = true }
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
            Button("仅 Bot 任务") { filter = .botTasksOnly }
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

    private func snoozeMenu(_ item: Item) -> some View {
        Menu("稍后") {
            ForEach(SnoozeChoice.allCases) { choice in
                Button(choice.title) { Task { await snooze(item, choice) } }
            }
        }
    }

    private func load() async {
        do {
            async let list = app.api.items()
            async let botList = app.api.bots()
            items = try await list.items
            bots = try await botList.bots
            notice = nil
            if let botID = app.pendingAgendaBotID {
                filter = .bot(botID)
                app.pendingAgendaBotID = nil
            }
            apply(app.pendingLink)
            await app.syncReminders()
        } catch {
            notice = .fromLoad(error, message: app.message(for: error))
        }
    }

    private func complete(_ item: Item) async {
        if (try? await app.api.completeItem(item.id)) != nil {
            completedCount += 1
        }
        await load()
    }

    private func snooze(_ item: Item, _ choice: SnoozeChoice) async {
        let until = choice.until()?.ISO8601Format()
        _ = try? await app.api.snoozeItem(item.id, minutes: choice.minutes(), until: until)
        await load()
    }

    private func remove(_ item: Item, scope: String) async {
        _ = try? await app.api.deleteReminder(item.id, scope: scope)
        pendingDelete = nil
        await load()
    }

    private func apply(_ link: DeepLink?) {
        guard let link else { return }
        switch link {
        case .reminder(let id):
            segment = 0
            if items.contains(where: { $0.id == id }) || items.isEmpty == false {
                viewingID = id
            }
            if items.isEmpty { return }
            if !items.contains(where: { $0.id == id }) { app.missingNotice = "内容已不存在" }
        case .reminders:
            segment = 0
        case .inbox:
            segment = 1
        default:
            return
        }
        app.pendingLink = nil
    }
}

private struct AgendaRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.reminder.done == 1 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.reminder.status == .due ? .red : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title).strikethrough(item.reminder.done == 1)
                    if item.reminder.priority >= 2 {
                        Image(systemName: "exclamationmark")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer(minLength: 0)
                    if let progress = item.checklistProgressText {
                        Text(progress)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.secondary)
                    }
                    if let task = item.task {
                        Text(task.status)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
                Text(ReminderTimeText.subtitle(item.reminder))
                    .font(.caption)
                    .foregroundStyle(item.reminder.status == .due ? .red : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
