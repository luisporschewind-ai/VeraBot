import SwiftUI
import VeraBotCore
import VeraBotData

struct DriftBottleRecordsView: View {
    @Environment(AppState.self) private var app
    @State private var filterBotID: Int?
    @State private var loading = false

    private var model: DriftBottleModel { app.driftBottle }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let notice = model.notice {
                    DriftBottleNoticeBanner(text: notice) { model.clearNotice() }
                }
                filter
                if loading && model.records.isEmpty {
                    ProgressView("正在翻找足迹…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 50)
                } else if model.records.isEmpty {
                    ContentUnavailableView("还没有足迹",
                                           systemImage: "shoeprints.fill",
                                           description: Text("捞到一封信、放漂一个新瓶，或只是和 Bot 安静读完，都会留在这里。"))
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(model.records) { record in
                            NavigationLink {
                                DriftBottleRecordDetailView(recordID: record.id)
                            } label: {
                                recordCard(record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if model.recordsNextCursor != nil {
                        Button {
                            Task { await model.loadMoreRecords(botID: filterBotID) }
                        } label: {
                            Label("加载更多", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle("我们的足迹")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.loadRecords(botID: filterBotID) }
        .task {
            if model.bots.isEmpty {
                if let bots = try? await app.api.bots().bots {
                    guard app.isCurrentSession(app.sessionGeneration) else { return }
                    model.updateBots(bots)
                }
            }
            await model.loadRecords(botID: filterBotID)
        }
        .onChange(of: filterBotID) { _, newValue in
            Task { await model.loadRecords(botID: newValue) }
        }
    }

    private var filter: some View {
        HStack {
            Text("按同行 Bot 筛选").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("全部") { filterBotID = nil }
                ForEach(model.bots) { bot in
                    Button(bot.name) { filterBotID = bot.id }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(filterBotID.flatMap { id in model.bots.first { $0.id == id }?.name } ?? "全部")
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.sectionFill, in: Capsule())
            }
        }
    }

    private func recordCard(_ record: DriftBottleRecordSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            BotAvatar(emoji: record.botAvatar, color: record.botColor, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandText)
                    .multilineTextAlignment(.leading)
                Text(record.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(record.kind == .encounter ? "相遇" : "放漂")
                    Text("·")
                    Text(record.createdDate, style: .date)
                    if record.hasMemory { Text("· 有回忆卡") }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(14)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DriftBottleRecordDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let recordID: String
    @State private var record: DriftBottleRecord?
    @State private var loading = true
    @State private var showingMemoryEdit = false
    @State private var showingDeleteRecord = false
    @State private var withdrawTarget: DriftBottlePublicContribution?
    @State private var blockTarget: DriftBottlePublicContribution?
    @State private var reportTarget: DriftBottlePublicContribution?
    @State private var reportReason = ""
    @State private var chatText = ""
    @State private var sending = false
    @State private var localNotice: String?

    private var model: DriftBottleModel { app.driftBottle }

    var body: some View {
        mainContent
            .themedPageBackground()
            .navigationTitle("这段经历")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .sheet(isPresented: $showingMemoryEdit) {
                if let record, let memory = record.memory, let encounter = record.encounter {
                    DriftBottleMemoryEditSheet(recordID: record.id, encounterID: encounter.id,
                                               memory: memory) { updated in
                        self.record = record.replacing(memory: updated)
                    }
                }
            }
            .alert("举报这段内容", isPresented: Binding(
                get: { reportTarget != nil },
                set: { if !$0 { reportTarget = nil } })) {
                TextField("举报原因", text: $reportReason)
                Button("提交举报") { submitReport() }
                Button("取消", role: .cancel) { reportTarget = nil }
            } message: {
                Text("举报会立刻对你隐藏这段内容，并进入管理员待处理队列。")
            }
            .confirmationDialog("撤回这段文字？", isPresented: Binding(
                get: { withdrawTarget != nil },
                set: { if !$0 { withdrawTarget = nil } }), presenting: withdrawTarget) { target in
                Button("撤回", role: .destructive) {
                    Task {
                        _ = await model.withdraw(contributionID: target.id)
                        withdrawTarget = nil
                        await load()
                    }
                }
                Button("取消", role: .cancel) { withdrawTarget = nil }
            } message: { _ in
                Text("原有位置会显示「这段文字已被收回」，不会破坏后面的阅读顺序。")
            }
            .confirmationDialog("屏蔽这位投稿者？", isPresented: Binding(
                get: { blockTarget != nil },
                set: { if !$0 { blockTarget = nil } }), presenting: blockTarget) { target in
                Button("屏蔽", role: .destructive) {
                    Task {
                        _ = await model.block(contributionID: target.id)
                        blockTarget = nil
                        await load()
                    }
                }
                Button("取消", role: .cancel) { blockTarget = nil }
            } message: { _ in
                Text("隐藏这位投稿者在当前记录中的文字，之后也不会再匹配到包含其内容的瓶子。")
            }
            .confirmationDialog("删除这条完整记录？", isPresented: $showingDeleteRecord) {
                Button("删除记录", role: .destructive) {
                    Task {
                        if await model.deleteRecord(id: recordID) { dismiss() }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只会删除你的私人记录、私人交流和回忆卡；已经公开的文字会继续留在瓶子里。")
            }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let notice = noticeText {
                    DriftBottleNoticeBanner(text: notice) {
                        localNotice = nil
                        model.clearNotice()
                    }
                }
                if let record {
                    detail(record)
                } else if loading {
                    ProgressView("正在取回这段经历…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    ContentUnavailableView("这条记录不在了",
                                           systemImage: "questionmark.folder",
                                           description: Text("它可能已经被删除，或属于另一个账号。"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var noticeText: String? { localNotice ?? model.notice }

    @ViewBuilder
    private func detail(_ record: DriftBottleRecord) -> some View {
        header(record)
        if let memory = record.memory {
            DriftBottleMemoryCardView(
                memory: memory,
                onEdit: { showingMemoryEdit = true },
                onRegenerate: { Task { await regenerateMemory(record) } },
                onDelete: { Task { await deleteMemory(record) } })
        } else if record.encounter != nil {
            memoryPrompt
        }
        if record.kind == .release, let release = record.release {
            releaseState(release)
        }
        letters(record)
        if let encounter = record.encounter {
            privateTurns(record, encounter: encounter)
            continueChat(record, encounter: encounter)
        }
        recordBoundary(record)
        Button(role: .destructive) {
            showingDeleteRecord = true
        } label: {
            Label("删除这条完整记录", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func submitReport() {
        guard let target = reportTarget else { return }
        Task {
            let ok = await model.report(contributionID: target.id,
                                        reason: reportReason.isEmpty ? "用户举报" : reportReason)
            reportTarget = nil
            reportReason = ""
            if ok { await load() }
        }
    }

    private var memoryPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有回忆卡").font(.subheadline.weight(.semibold))
            Text("可以请 Bot 根据这次实际读到和聊到的内容整理一张卡片；不会写入普通聊天或长期记忆。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { if let record { await regenerateMemory(record) } }
            } label: {
                Label("整理共同回忆", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .disabled(model.isWorking)
        }
        .padding(14)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 16))
    }

    private func header(_ record: DriftBottleRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let encounter = record.encounter {
                BotAvatar(emoji: encounter.botAvatar, color: encounter.botColor, size: 44)
            } else if let release = record.release {
                BotAvatar(emoji: release.botAvatar, color: release.botColor, size: 44)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.title3.bold()).foregroundStyle(Color.brandText)
                Text(record.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let completed = record.completedDate {
                    Text("完成于 \(completed.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func releaseState(_ release: DriftBottleRelease) -> some View {
        HStack(spacing: 8) {
            Image(systemName: release.state == "archived" ? "archivebox" : "water.waves")
                .foregroundStyle(Color.brandAccent)
            Text(release.state == "archived"
                 ? "这个瓶子已经收满 50 条投稿，不再进入匹配池。"
                 : "这个瓶子仍在海面漂流；你看到的只是自己公开过的文字。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func letters(_ record: DriftBottleRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DriftBottleSectionTitle(title: "这次留下的公开文字",
                                    subtitle: "只有这里的内容会随瓶漂流")
            if record.contributions.isEmpty {
                Text("没有公开留言。安静读完、直接放回同样是一次完整的相遇。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(record.contributions) { item in
                DriftBottleContributionCard(
                    contribution: item,
                    onWithdraw: item.canWithdraw ? { withdrawTarget = item } : nil,
                    onReport: item.canReport ? { reportTarget = item; reportReason = "" } : nil,
                    onBlock: item.canReport ? { blockTarget = item } : nil)
            }
        }
    }

    @ViewBuilder
    private func privateTurns(_ record: DriftBottleRecord, encounter: DriftBottleEncounter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            DriftBottleSectionTitle(title: "你和 \(encounter.botName) 的私人交流",
                                    subtitle: "只属于你们，不会随瓶公开")
            if record.turns.filter(\.isPrivate).isEmpty {
                Text("这次没有私下聊天，也可以带着安静读过的内容离开。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(record.turns.filter(\.isPrivate)) { turn in
                HStack(alignment: .top, spacing: 8) {
                    if turn.role == .bot {
                        BotAvatar(emoji: encounter.botAvatar, color: encounter.botColor, size: 24)
                    }
                    Text(turn.content)
                        .font(.subheadline)
                        .padding(10)
                        .background(turn.role == .bot ? Color.brandSoft : Color.sectionFill,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private func continueChat(_ record: DriftBottleRecord, encounter: DriftBottleEncounter) -> some View {
        if encounter.botID != nil, !encounter.botDeleted {
            VStack(alignment: .leading, spacing: 8) {
                Text("还想和它聊聊这次相遇吗？")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("只属于你和 Bot 的话", text: $chatText, axis: .vertical)
                        .lineLimit(1...4)
                        .themedFieldBackground()
                    Button {
                        Task { await submitChat(record, encounter: encounter) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandFill)
                    .disabled(sending || DriftBottlePresentation.validateChat(chatText) != nil)
                    .accessibilityLabel("发送私人消息")
                }
                Text("这里不会再追加公开留言；这次交流仍只属于你。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func recordBoundary(_ record: DriftBottleRecord) -> some View {
        Text(record.encounter == nil
             ? "删除这条记录只会隐藏你的放漂足迹，不会撤回别人已经看到的公开文字。"
             : "删除这条记录会清掉私人交流与回忆卡，但不会撤回已经公开的文字，也不会清除「已读」去重标记。")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        record = await model.record(id: recordID)
    }

    private func regenerateMemory(_ record: DriftBottleRecord) async {
        guard let encounter = record.encounter else { return }
        if let updated = await model.generateMemory(encounterID: encounter.id) {
            self.record = record.replacing(memory: updated)
        } else {
            localNotice = model.notice ?? "这次没有整理成功，原来的记录还在。"
        }
    }

    private func deleteMemory(_ record: DriftBottleRecord) async {
        if await model.deleteMemory(recordID: record.id) {
            self.record = record.replacing(memory: nil)
        } else {
            localNotice = model.notice ?? "这次没有删除成功。"
        }
    }

    private func submitChat(_ record: DriftBottleRecord,
                            encounter: DriftBottleEncounter) async {
        let text = chatText
        sending = true
        defer { sending = false }
        if await model.send(message: text, to: encounter.id) != nil {
            if let refreshed = await model.record(id: recordID) { self.record = refreshed }
            chatText = ""
        } else {
            localNotice = model.notice ?? "这句话没有送到，文字还在。"
        }
    }
}
