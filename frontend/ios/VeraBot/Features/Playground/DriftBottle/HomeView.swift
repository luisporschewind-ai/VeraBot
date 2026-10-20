import SwiftUI
import VeraBotCore
import VeraBotData
import VeraBotNetworking

// MARK: - Shared small components

struct DriftBottleSectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Color.brandText)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct DriftBottleNoticeBanner: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.brandAccent)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .padding(14)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Public Bot signature: only the confirmed display name and the preset emoji
/// avatar are shown. It never fetches the other account's photo avatar.
struct DriftBottleBotSignature: View {
    let name: String
    let avatar: String
    let color: String
    var size: CGFloat = 26
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            BotAvatar(emoji: avatar, color: color, size: size)
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.brandText)
            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Home

struct DriftBottleHomeView: View {
    @Environment(AppState.self) private var app
    @Environment(BotTravelStore.self) private var travelStore
    @State private var showingBotPicker = false
    @State private var showingComposer = false
    @State private var showingRecords = false
    @State private var openedEncounter: DriftBottleEncounter?
    @State private var completedRecord: DriftBottleRecord?
    @State private var publishedNotice: String?
    @State private var loadingBots = false

    private var model: DriftBottleModel { app.driftBottle }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let notice = model.notice {
                    DriftBottleNoticeBanner(text: notice) { model.clearNotice() }
                }
                if let publishedNotice {
                    DriftBottleNoticeBanner(text: publishedNotice) { self.publishedNotice = nil }
                }
                if model.bots.isEmpty {
                    noBotCard
                } else {
                    companionCard
                    if model.current != nil {
                        currentBottleCard
                    }
                    primaryActions
                    if model.isEmptyPool {
                        emptyPoolCard
                    }
                }
                footprintsLink
                boundaryCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle("Bot 漂流瓶")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBots()
            if model.state == nil { await model.load() }
        }
        .sheet(isPresented: $showingBotPicker) {
            botPicker
        }
        .sheet(isPresented: $showingComposer) {
            if let bot = model.selectedBot {
                NavigationStack {
                    DriftBottleComposerView(mode: .newBottle(botID: bot.id, botName: bot.name,
                                                             botAvatar: bot.avatar,
                                                             botColor: bot.color)) { record in
                        showingComposer = false
                        if record != nil {
                            completedRecord = record
                        } else {
                            publishedNotice = "新瓶已经放漂了。海面会把它带到下一位读到的人那里。"
                        }
                    }
                }
            }
        }
        .sheet(item: $completedRecord) { record in
            DriftBottleCompletionSheet(record: record)
        }
        .navigationDestination(item: $openedEncounter) { encounter in
            DriftBottleReadingView(encounterID: encounter.id)
        }
        .navigationDestination(isPresented: $showingRecords) {
            DriftBottleRecordsView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "water.waves")
                    .font(.title2)
                    .foregroundStyle(Color.brandAccent)
                Text("海面带来的，不一定是回音")
                    .font(.title2.bold())
                    .foregroundStyle(Color.brandText)
            }
            Text("和你的 Bot 一起读一封陌生人的来信，聊聊你们各自看见的东西。是否留下文字、留下什么，都由你决定。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var companionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DriftBottleSectionTitle(title: "这次和谁一起", subtitle: "拿到的瓶子会记住这位同行 Bot，读到一半不会换人")
            if let bot = model.selectedBot {
                HStack(spacing: 12) {
                    LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                                  hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt,
                                  size: 46, action: .idle, appearance: bot.supportedAppearance)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bot.name).font(.headline).foregroundStyle(Color.brandText)
                        Text(travelStore.activeTrip(botID: bot.id) == nil
                             ? "同行伙伴" : "还在旅途中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.hasActiveEncounter ? "这次已锁定" : "换一位") {
                        showingBotPicker = true
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .disabled(model.hasActiveEncounter)
                }
            }
        }
        .padding(16)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var currentBottleCard: some View {
        Group {
            if let current = model.current {
                if current.isActive {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            DriftBottleSectionTitle(title: "手里正拿着一个瓶子",
                                                    subtitle: "第 1 站之后，瓶子已经带着 \(max(0, current.readLimit - 1)) 条沿途留言")
                            Spacer()
                            Image(systemName: "envelope.open.fill")
                                .foregroundStyle(Color.brandAccent)
                        }
                        HStack(spacing: 12) {
                            BotAvatar(emoji: current.botAvatar, color: current.botColor, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("和 \(current.botName) 一起读").font(.subheadline.weight(.semibold))
                                Text(DriftBottlePresentation.remainingText(
                                    seconds: current.remainingSeconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("继续读") { openedEncounter = current }
                                .accessibilityIdentifier("drift.continue")
                                .buttonStyle(.borderedProminent)
                                .tint(Color.brandFill)
                        }
                    }
                    .padding(16)
                    .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    endedCard(current)
                }
            } else if model.isOffline, let cached = model.cachedEncounter {
                VStack(alignment: .leading, spacing: 10) {
                    DriftBottleSectionTitle(title: "上次的相遇还在本机",
                                            subtitle: "私人对话和草稿没有丢；信件内容需要联网更新")
                    Text("和 \(cached.botName) 说过的话仍可查看。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("等待联网更新") { Task { await model.load() } }
                        .buttonStyle(.bordered)
                }
                .padding(16)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func endedCard(_ current: DriftBottleEncounter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DriftBottleSectionTitle(title: "这次相遇已经收好",
                                    subtitle: current.endReason == .expired
                                    ? "持有时间到了。回忆和私人交流仍保留在足迹里。" : "放回或放漂后，这段经历已经记下。")
            NavigationLink {
                DriftBottleRecordDetailView(recordID: "encounter:\(current.id)")
            } label: {
                Label("查看这次回忆", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var primaryActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                actionButton(title: "捞一个瓶子", subtitle: "看看海面带来了什么",
                             symbol: "water.waves", prominent: true) {
                    Task {
                        guard let bot = model.selectedBot else { return }
                        if let encounter = await model.draw(botID: bot.id) {
                            openedEncounter = encounter
                        }
                    }
                }
                .disabled(model.hasActiveEncounter || model.isWorking || loadingBots)
                .accessibilityIdentifier("drift.draw")

                actionButton(title: "写一个新瓶", subtitle: "把自己的话放进海里",
                             symbol: "square.and.pencil", prominent: false) {
                    showingComposer = true
                }
                .disabled(model.isWorking || model.selectedBot == nil)
                .accessibilityIdentifier("drift.write")
            }
        }
    }

    private func actionButton(title: String, subtitle: String, symbol: String,
                              prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3)
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .opacity(0.8)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(prominent ? Color.white : Color.brandText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(prominent ? Color.brandFill : Color.sectionFill,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(model.isWorking ? 0.6 : 1)
    }

    private var emptyPoolCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "water.waves")
                Text("海面暂时很安静").font(.headline)
            }
            Text("现在没有可捞的瓶子。可以稍后再试，也可以先写一个自己的瓶子，让它带着你的话去遇见别人。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("再试一次") {
                    Task {
                        guard let bot = model.selectedBot else { return }
                        if let encounter = await model.draw(botID: bot.id) {
                            openedEncounter = encounter
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandFill)
                Button("写一个新瓶") { showingComposer = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var footprintsLink: some View {
        Button { showingRecords = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "shoeprints.fill")
                    .foregroundStyle(Color.brandAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("我们的足迹").font(.subheadline.weight(.semibold))
                    Text("读过的信、放漂的新瓶和共同回忆")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("drift.records")
    }

    private var boundaryCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.brandAccent)
            Text("这里的交流只属于你和 Bot。只有你确认过的文字才会随瓶漂流，不会带出整段私人对话、账号或完整人设。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var noBotCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有 Bot 伙伴").font(.headline)
            Text("先到 Bot 页创建一位有自己性格的 Bot，再回来和它一起读信。没有 Bot 时，海面不会替你虚构一位同行者。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var botPicker: some View {
        NavigationStack {
            List {
                ForEach(model.bots) { bot in
                    let traveling = travelStore.activeTrip(botID: bot.id) != nil
                    Button {
                        model.selectBot(bot.id)
                        showingBotPicker = false
                    } label: {
                        HStack(spacing: 12) {
                            LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                                          hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt,
                                          size: 40, appearance: bot.supportedAppearance)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bot.name).foregroundStyle(Color.brandText)
                                Text(traveling ? "还在旅途中，暂时不能一起出发"
                                     : (bot.persona.isEmpty ? "可以做你的同行伙伴" : bot.persona))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if model.selectedBotID == bot.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.brand)
                            }
                        }
                    }
                    .disabled(traveling)
                }
            }
            .navigationTitle("这次和谁一起")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingBotPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadBots() async {
        guard app.token != nil else { return }
        let generation = app.sessionGeneration
        loadingBots = true
        defer { loadingBots = false }
        do {
            let bots = try await app.api.bots().bots
            guard app.isCurrentSession(generation) else { return }
            model.updateBots(bots)
        } catch {
            // The state request already provides an explicit failure notice.
        }
    }
}
