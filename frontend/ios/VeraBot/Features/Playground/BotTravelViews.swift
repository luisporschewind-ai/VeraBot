import SwiftUI
import VeraBotCore

struct BotTravelStartView: View {
    @Environment(AppState.self) private var app
    @Environment(BotTravelStore.self) private var travelStore
    @State private var bots: [Bot] = []
    @State private var selectedBotID: Int?
    @State private var destinationID: String?
    @State private var theme = ""
    @State private var note = ""
    @State private var loading = false
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var journey: BotTravelTrip?
    @State private var showingAlbum = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var selectedDestination: BotTravelDestination? {
        destinationID.flatMap(BotTravelDestination.find)
    }
    private var selectedBot: Bot? { bots.first { $0.id == selectedBotID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                intro
                activeTrips
                botPicker
                destinationPicker
                if let selectedDestination { themePicker(for: selectedDestination) }
                noteField
                startButton
                privacyNote
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle("Bot 旅行")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("旅行相册") { showingAlbum = true }
            }
        }
        .task { await loadBots() }
        .sheet(isPresented: $showingAlbum) {
            NavigationStack { BotTravelAlbumView() }
        }
        .navigationDestination(item: $journey) { trip in
            BotTravelJourneyView(trip: trip)
                .toolbar(.hidden, for: .tabBar)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("一段慢慢展开的旅程", systemImage: "map")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.brand)
            Text("派一位伙伴出发")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.brandText)
            Text("选一座城市和一个方向。它会带着你的话出发，途中给你寄来线索，最后把旅札和纪念卡带回来。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var botPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("邀请哪位伙伴", subtitle: "旅行中的 Bot 会暂时专心探索")
            if loading && bots.isEmpty {
                ProgressView("正在找你的伙伴…").frame(maxWidth: .infinity, minHeight: 76)
            } else if let loadError {
                ContentUnavailableView {
                    Label("暂时没能加载伙伴", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("再试一次") { Task { await loadBots() } }
                        .prominentButtonStyle()
                }
            } else if bots.isEmpty {
                ContentUnavailableView("还没有 Bot 伙伴", systemImage: "person.crop.circle.badge.plus",
                                       description: Text("先创建一位 Bot，再邀请它去旅行。"))
            } else {
                VStack(spacing: 9) {
                    ForEach(bots) { bot in
                        let traveling = travelStore.activeTrip(botID: bot.id) != nil
                        Button {
                            selectedBotID = bot.id
                        } label: {
                            HStack(spacing: 12) {
                                LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                                              hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt, size: 46)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bot.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text(traveling ? "还在旅途中" : (bot.persona.isEmpty ? "准备出发" : bot.persona))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if traveling {
                                    Image(systemName: "airplane").foregroundStyle(Color.brand)
                                } else if selectedBotID == bot.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
                                }
                            }
                            .padding(12)
                            .background(selectedBotID == bot.id ? Color.brandSoft : Color.sectionFill,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selectedBotID == bot.id ? Color.brand.opacity(0.45) : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(traveling)
                        .accessibilityLabel("\(bot.name)\(traveling ? "，旅行中" : "")")
                    }
                }
            }
        }
    }

    private var activeTrips: some View {
        let trips = travelStore.trips.filter { $0.stage(at: travelStore.now) != .returned }
        return Group {
            if !trips.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeading("正在旅途", subtitle: "继续查看已经揭晓的消息")
                    ForEach(trips) { trip in
                        NavigationLink {
                            BotTravelJourneyView(trip: trip)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: trip.destination?.symbol ?? "map")
                                    .font(.title3).foregroundStyle(Color.brand)
                                    .frame(width: 44, height: 44)
                                    .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(trip.botAvatar) \(trip.botName) 正在\(trip.destination?.city ?? "旅行")")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text("\(trip.theme) · 约还需 \(clockText(trip.remaining(at: travelStore.now)))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("去哪里看看", subtitle: "精选六座城市，每趟旅程聚焦一个主题")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(BotTravelDestination.all) { destination in
                    let selected = destinationID == destination.id
                    Button {
                        destinationID = destination.id
                        if !destination.themes.contains(theme) { theme = destination.themes[0] }
                    } label: {
                        VStack(alignment: .leading, spacing: 11) {
                            Image(systemName: destination.symbol)
                                .font(.title2)
                                .foregroundStyle(selected ? Color.brand : Color.brandAccent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(destination.city).font(.headline).foregroundStyle(.primary)
                                Text(destination.region).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(destination.themes[0])
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.brand)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
                        .padding(13)
                        .background(selected ? Color.brandSoft : Color.sectionFill,
                                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(selected ? Color.brand.opacity(0.45) : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func themePicker(for destination: BotTravelDestination) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("这趟想看什么", subtitle: destination.city)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(destination.themes, id: \.self) { item in
                        let selected = item == theme
                        Button(item) { theme = item }
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .buttonStyle(.bordered)
                            .tint(selected ? Color.brand : Color.secondary)
                    }
                }
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeading("留一句出发的话", subtitle: "可选；它会出现在这趟旅程里")
            TextField("例如：找一个适合安静散步的地方", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .padding(13)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 15))
                .onChange(of: note) { _, value in if value.count > 100 { note = String(value.prefix(100)) } }
        }
    }

    private var startButton: some View {
        VStack(spacing: 8) {
            Button(action: startTrip) {
                Label("送它出发", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .disabled(selectedBot == nil || selectedDestination == nil || theme.isEmpty ||
                      (selectedBot.map { travelStore.activeTrip(botID: $0.id) != nil } ?? false))
            if let actionError {
                Text(actionError).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var privacyNote: some View {
        Label("这是一趟五分钟的体验版旅程，记录只保存在本机。", systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func loadBots() async {
        loading = true
        defer { loading = false }
        do {
            let session = app.sessionGeneration
            let response = try await app.api.bots()
            guard app.isCurrentSession(session) else { return }
            bots = BotOrdering.sorted(response.bots)
            if selectedBotID == nil, let first = bots.first(where: { travelStore.activeTrip(botID: $0.id) == nil }) {
                selectedBotID = first.id
            }
            loadError = nil
        } catch {
            loadError = app.message(for: error)
        }
    }

    private func startTrip() {
        guard let bot = selectedBot, let destination = selectedDestination else { return }
        do {
            journey = try travelStore.startTrip(bot: bot, destinationID: destination.id,
                                               theme: theme, note: note)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func clockText(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct BotTravelJourneyView: View {
    let trip: BotTravelTrip
    @Environment(BotTravelStore.self) private var travelStore

    private var destination: BotTravelDestination? { trip.destination }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let stage = trip.stage(at: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    journeyHeader(stage: stage, now: now)
                    ForEach(BotTravelStage.allCases.filter { $0.rawValue <= stage.rawValue }) { item in
                        stageCard(item)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if stage != .returned { nextStageHint(stage: stage) }
                    else { Label("这趟旅程已收进旅行相册。", systemImage: "books.vertical")
                        .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center) }
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.35), value: stage)
            }
            .themedPageBackground()
        }
        .navigationTitle(destination?.city ?? "旅行")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { travelStore.refresh() }
    }

    private func journeyHeader(stage: BotTravelStage, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(stage == .returned ? "旅程归来" : "正在旅途中")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.brand)
                    Text(destination?.city ?? "未知地点")
                        .font(.largeTitle.bold()).foregroundStyle(Color.brandText)
                    Text("\(trip.botName) · \(trip.theme)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(trip.botAvatar).font(.largeTitle)
                    .frame(width: 54, height: 54)
                    .background(Color.brandSoft, in: Circle())
            }
            ProgressView(value: trip.progress(at: now))
                .tint(Color.brand)
            if stage == .returned {
                Label("已平安回来", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(Color.brand)
            } else {
                Text("大约还要 \(clockText(trip.remaining(at: now)))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(BotTravelStage.allCases) { item in
                    VStack(spacing: 5) {
                        Circle().fill(item.rawValue <= stage.rawValue ? Color.brand : Color.secondary.opacity(0.22))
                            .frame(width: 9, height: 9)
                        Text(item.title).font(.caption2)
                            .foregroundStyle(item.rawValue <= stage.rawValue ? Color.brand : Color.secondary)
                    }
                    if item != BotTravelStage.allCases.last { Spacer(minLength: 0) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func stageCard(_ stage: BotTravelStage) -> some View {
        switch stage {
        case .departed:
            VStack(alignment: .leading, spacing: 10) {
                Label("已经出发", systemImage: "paperplane.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.brand)
                Text(trip.note.isEmpty ? "我先去 \(destination?.city ?? "远方") 看看「\(trip.theme)」。回来时给你带一张旅札。" : "我记着你留的话：「\(trip.note)」现在出发啦。")
                    .font(.body).fixedSize(horizontal: false, vertical: true)
            }
            .travelCard()
        case .clue:
            VStack(alignment: .leading, spacing: 10) {
                Label("途中线索", systemImage: "sparkle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.brand)
                Text(destination?.clue ?? "我发现了一点有趣的线索。")
                    .font(.body).fixedSize(horizontal: false, vertical: true)
            }
            .travelCard()
        case .discovery:
            VStack(alignment: .leading, spacing: 14) {
                Label("地点发现 · 有来源", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.brand)
                Text(destination?.factTitle ?? "旅途发现").font(.headline)
                Text(destination?.fact ?? "")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                if let destination {
                    Link(destination.sourceTitle, destination: destination.sourceURL)
                        .font(.caption.weight(.medium))
                }
                Divider()
                Label("Bot 的旅途想象", systemImage: "cloud")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.brandAccent)
                Text(destination.map { imagination(for: $0) } ?? "这段感受是 Bot 为旅程写下的想象。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
            .travelCard()
        case .returned:
            VStack(alignment: .leading, spacing: 14) {
                Label("给你的归来旅札", systemImage: "envelope.open")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.brand)
                Text("从\(destination?.city ?? "旅途")带回来的发现")
                    .font(.title3.bold()).foregroundStyle(Color.brandText)
                Text(destination.map { imagination(for: $0) } ?? "旅途里有些风景，我想讲给你听。")
                    .font(.body).fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                if let destination {
                    HStack(spacing: 12) {
                        Image(systemName: destination.keepsakeSymbol)
                            .font(.title2).foregroundStyle(Color.brand)
                            .frame(width: 52, height: 52)
                            .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(destination.keepsakeName).font(.subheadline.weight(.semibold))
                            Text(destination.keepsakeStory).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 17))
                    Text("地点事实与来源见「地点发现」；这段旅途感受是 Bot 的想象。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .travelCard()
        }
    }

    private func nextStageHint(stage: BotTravelStage) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.brand)
            Text(stage == .departed ? "路上有新的发现时，我会再寄给你。" : "旅程还在继续，等它回来再读完整旅札。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private func imagination(for destination: BotTravelDestination) -> String {
        if trip.note.isEmpty { return destination.imagination }
        return "我带着你留的话「\(trip.note)」一路看看。\(destination.imagination)"
    }

    private func clockText(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct BotTravelAlbumView: View {
    @Environment(BotTravelStore.self) private var travelStore
    @State private var pendingDelete: BotTravelTrip?

    private var completedTrips: [BotTravelTrip] {
        travelStore.trips.filter { $0.stage(at: travelStore.now) == .returned }
    }

    var body: some View {
        List {
            if completedTrips.isEmpty {
                ContentUnavailableView("相册还空着", systemImage: "books.vertical",
                                       description: Text("完成一次旅行后，旅札和纪念卡会收在这里。"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(completedTrips) { trip in
                    NavigationLink {
                        BotTravelJourneyView(trip: trip)
                    } label: {
                        albumRow(trip)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = trip } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .themedPageBackground()
        .navigationTitle("旅行相册")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("删除这段旅行记录？", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { trip in
            Button("删除记录", role: .destructive) { travelStore.deleteTrip(id: trip.id) }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("删除后，这张旅札和纪念卡会从本机相册移除。")
        }
    }

    private func albumRow(_ trip: BotTravelTrip) -> some View {
        let destination = trip.destination
        let stage = trip.stage(at: travelStore.now)
        return HStack(spacing: 13) {
            Image(systemName: destination?.keepsakeSymbol ?? "map")
                .font(.title2).foregroundStyle(Color.brand)
                .frame(width: 48, height: 48)
                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(destination?.city ?? "旅行") · \(trip.theme)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(trip.botAvatar) \(trip.botName) · \(stage == .returned ? (destination?.keepsakeName ?? "已归来") : stage.title)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }
}

private extension View {
    func travelCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}
