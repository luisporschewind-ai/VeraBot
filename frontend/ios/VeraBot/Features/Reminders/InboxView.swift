import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct InboxView: View {
    @Environment(AppState.self) private var app
    @State private var items: [InboxNotification] = []
    @State private var category: String?
    @State private var errorText: String?
    /// 列表第一个分组的头（提醒页传入「提醒／通知」分段），随列表滚动、位于大标题下方
    var header: AnyView = AnyView(EmptyView())

    var body: some View {
        ThemedList {
            Section { } header: { header }
            ForEach(items) { item in
                Button { Task { await open(item) } } label: { row(item) }
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) { Task { await remove(item) } }
                    }
                    .swipeActions(edge: .leading) {
                        if item.isUnread {
                            Button("标为已读") { Task { await mark(item, read: true) } }.tint(.green)
                        } else {
                            Button("标为未读") { Task { await mark(item, read: false) } }
                        }
                    }
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .overlay {
            if items.isEmpty && errorText == nil {
                ContentUnavailableView("没有通知", systemImage: "bell", description: Text("新的提醒和消息会出现在这里"))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("全部已读") { Task { await readAll() } }
            }
            ToolbarItem(placement: .topBarLeading) { categoryMenu }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ item: InboxNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if item.isUnread {
                Circle().fill(Color.brand).frame(width: 8, height: 8).padding(.top, 6)
            }
            Image(systemName: item.category.systemImage)
                .foregroundStyle(Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body)
                if let body = item.body, !body.isEmpty {
                    Text(body).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let created = item.createdAt {
                    Text(relative(created)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryMenu: some View {
        Menu("分类") {
            Button("全部") { category = nil; Task { await load() } }
            ForEach(["reminder", "bot_message", "delegation", "plugin", "system"], id: \.self) { raw in
                Button((NotificationCategory(rawValue: raw) ?? .unknown).title) {
                    category = raw
                    Task { await load() }
                }
            }
        }
    }

    private func load() async {
        do {
            let response = try await app.api.notifications(unread: false, category: category)
            items = response.notifications
            app.unreadCount = response.unreadCount
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func open(_ item: InboxNotification) async {
        _ = try? await app.api.markNotificationRead(item.id)
        if let link = item.link { await app.open(link: link) }
        await load()
    }

    private func mark(_ item: InboxNotification, read: Bool) async {
        if read {
            _ = try? await app.api.markNotificationRead(item.id)
        } else {
            _ = try? await app.api.markNotificationUnread(item.id)
        }
        await load()
    }

    private func readAll() async {
        _ = try? await app.api.markAllNotificationsRead()
        await load()
    }

    private func remove(_ item: InboxNotification) async {
        _ = try? await app.api.deleteNotification(item.id)
        await load()
    }

    private func relative(_ text: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: text) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
