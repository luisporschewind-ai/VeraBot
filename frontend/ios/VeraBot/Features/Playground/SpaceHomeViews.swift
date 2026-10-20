import SwiftUI
import VeraBotCore
import VeraBotNetworking

/// 空间页主体：Bot 团队状态、正在继续、共同纪念。
struct SpaceHomeContent: View {
    @Environment(AppState.self) private var app
    @Environment(BotTravelStore.self) private var travelStore

    @State private var bots: [Bot] = []
    @State private var notice: PageNotice?
    @State private var loading = false
    @State private var activeTasksByBot: [Int: SpaceActiveTask] = [:]
    @State private var chatBot: Bot?
    @State private var journeyTrip: BotTravelTrip?
    @State private var showingAlbum = false

    private let memoryColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    botTeamSection(now: now)
                    continueSection(now: now)
                    memoriesSection(now: now)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationDestination(item: $chatBot) { bot in
            ChatView(bot: bot, api: app.api, repository: app.conversationRepository)
                .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(item: $journeyTrip) { trip in
            BotTravelJourneyView(trip: trip)
                .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(isPresented: $showingAlbum) {
            BotTravelAlbumView()
                .toolbar(.hidden, for: .tabBar)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .onAppear { travelStore.refresh() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func botTeamSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WorldSectionTitle(title: "Bot 团队", subtitle: "看看伙伴们此刻在做什么")
            if loading && bots.isEmpty {
                ProgressView("正在找你的伙伴…")
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else if let notice {
                PageConnectionNotice(notice: notice, retrying: loading) {
                    Task { await reload() }
                }
            } else if bots.isEmpty {
                Text("还没有 Bot 伙伴，可以去「助理」创建一个。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(bots) { bot in
                            Button {
                                chatBot = bot
                            } label: {
                                SpaceBotChip(bot: bot, activity: activity(for: bot, now: now))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func continueSection(now: Date) -> some View {
        let activeTrip = travelStore.trips.first { $0.stage(at: now) != .returned }
        let task = firstActiveTask
        switch SpaceHomeLogic.continueKind(hasActiveTrip: activeTrip != nil, hasActiveTask: task != nil) {
        case .trip:
            if let trip = activeTrip {
                Button {
                    journeyTrip = trip
                } label: {
                    SpaceContinueCard(
                        symbol: "map",
                        title: "\(trip.botName) 正在旅行",
                        subtitle: "\(trip.destination?.city ?? "旅途中") · \(trip.theme)"
                    )
                }
                .buttonStyle(.plain)
            }
        case .task:
            if let task {
                Button {
                    if let bot = bots.first(where: { $0.id == task.botID }) {
                        chatBot = bot
                    }
                } label: {
                    SpaceContinueCard(
                        symbol: "arrow.turn.down.right",
                        title: task.title,
                        subtitle: bots.first(where: { $0.id == task.botID })?.name ?? task.botName
                    )
                }
                .buttonStyle(.plain)
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func memoriesSection(now: Date) -> some View {
        let returned = travelStore.trips
            .filter { $0.stage(at: now) == .returned }
            .sorted { $0.startedAt > $1.startedAt }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                WorldSectionTitle(title: "共同纪念", subtitle: "一起留下的旅札与纪念卡")
                Spacer(minLength: 8)
                if !returned.isEmpty {
                    Button("旅行相册") { showingAlbum = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brand)
                }
            }

            if returned.isEmpty {
                Text("一起完成一次旅行后，纪念卡会留在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: memoryColumns, spacing: 12) {
                    ForEach(returned) { trip in
                        Button {
                            journeyTrip = trip
                        } label: {
                            SpaceMemoryCard(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Data

    private var firstActiveTask: SpaceActiveTask? {
        bots.compactMap { activeTasksByBot[$0.id] }.first
    }

    private func activity(for bot: Bot, now: Date) -> SpaceBotActivity {
        let city = travelStore.activeTrip(botID: bot.id, at: now)?.destination?.city
        return SpaceHomeLogic.activity(
            travelingCity: city,
            hasActiveTask: activeTasksByBot[bot.id] != nil
        )
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        travelStore.refresh()
        await loadBots()
        await loadTasks()
    }

    private func loadBots() async {
        do {
            let response = try await app.api.bots()
            guard app.token != nil else { return }
            bots = BotOrdering.sorted(response.bots)
            for bot in response.bots {
                app.avatars.reconcileBot(id: bot.id, hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt)
            }
            notice = nil
        } catch {
            notice = .fromLoad(error, message: app.message(for: error))
        }
    }

    private func loadTasks() async {
        // 失败静默降级：不展示「正在执行任务」。
        let items = (try? await app.api.items(view: "bot").items) ?? []
        var map: [Int: SpaceActiveTask] = [:]
        for item in items {
            guard let task = item.task,
                  SpaceHomeLogic.isActiveBotTask(statusKey: task.statusKey, needsUser: task.needsUser),
                  let botID = task.botId ?? item.reminder.assigneeBotId ?? item.reminder.sourceBotId
            else { continue }
            if map[botID] != nil { continue }
            let botName = bots.first(where: { $0.id == botID })?.name ?? item.reminder.sourceName
            let trimmed = task.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            map[botID] = SpaceActiveTask(
                id: item.id,
                botID: botID,
                title: trimmed.isEmpty ? item.title : trimmed,
                botName: botName
            )
        }
        activeTasksByBot = map
    }
}

private struct SpaceActiveTask: Identifiable, Equatable {
    let id: Int
    let botID: Int
    let title: String
    let botName: String
}

private struct SpaceBotChip: View {
    let bot: Bot
    let activity: SpaceBotActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiveBotAvatar(
                botID: bot.id, emoji: bot.avatar, color: bot.color,
                hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt, size: 44,
                appearance: bot.supportedAppearance
            )
            Text(bot.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(activity.label)
                .font(.caption2)
                .foregroundStyle(activity == .idle ? Color.secondary : Color.brand)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 108, alignment: .leading)
        .padding(12)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SpaceContinueCard: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("正在继续", systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brand)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SpaceMemoryCard: View {
    let trip: BotTravelTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: trip.destination?.keepsakeSymbol ?? "heart.text.square")
                .font(.title2)
                .foregroundStyle(Color.brandAccent)
                .frame(width: 48, height: 48)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.destination?.keepsakeName ?? "纪念卡")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(trip.destination?.city ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(trip.botAvatar)
                    .font(.caption)
                Text(trip.botName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .padding(14)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
