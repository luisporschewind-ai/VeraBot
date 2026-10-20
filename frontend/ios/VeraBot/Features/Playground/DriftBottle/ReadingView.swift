import SwiftUI
import VeraBotCore
import VeraBotData
import VeraBotNetworking

struct DriftBottleContributionCard: View {
    let contribution: DriftBottlePublicContribution
    var onWithdraw: (() -> Void)?
    var onReport: (() -> Void)?
    var onBlock: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(contribution.sequence == 1 ? "原信" : "沿途留言")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
                Text("第 \(contribution.sequence) 站")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if onWithdraw != nil || onReport != nil || onBlock != nil {
                    Menu {
                        if let onWithdraw {
                            Button("撤回这段文字", systemImage: "arrow.uturn.backward", action: onWithdraw)
                        }
                        if let onReport {
                            Button("举报…", systemImage: "flag", action: onReport)
                        }
                        if let onBlock {
                            Button("屏蔽这位投稿者", systemImage: "person.crop.circle.badge.xmark", action: onBlock)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("这段文字的操作")
                }
            }
            Text(contribution.body)
                .font(.body)
                .foregroundStyle(contribution.isReadable ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                DriftBottleBotSignature(name: contribution.botName,
                                        avatar: contribution.botAvatar,
                                        color: contribution.botColor,
                                        size: 22,
                                        trailing: contribution.authorship.shortLabel)
                Spacer()
                Text(contribution.createdDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(contribution.sequence == 1 ? Color.brandAccent : Color.brand.opacity(0.35))
                .frame(width: 3)
                .padding(.vertical, 12)
        }
    }
}

struct DriftBottleReadingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let encounterID: Int
    @State private var showingComposer = false
    @State private var completedRecord: DriftBottleRecord?
    @State private var reportTarget: DriftBottlePublicContribution?
    @State private var withdrawTarget: DriftBottlePublicContribution?
    @State private var blockTarget: DriftBottlePublicContribution?
    @State private var reportReason = ""
    @State private var blockAfterReport = false
    @State private var showingReturnConfirm = false
    @State private var loading = false
    @State private var didRequestOpening = false

    private var model: DriftBottleModel { app.driftBottle }
    private var encounter: DriftBottleEncounter? {
        model.current?.id == encounterID ? model.current : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let notice = model.notice {
                    DriftBottleNoticeBanner(text: notice) { model.clearNotice() }
                }
                if let encounter {
                    header(encounter)
                    if model.isOffline {
                        offlineBanner
                    }
                    letters(encounter)
                    privateSection(encounter)
                    footer(encounter)
                } else if let cached = model.cachedEncounter, cached.id == encounterID {
                    offlineReading(cached)
                } else if loading || model.isLoading {
                    ProgressView("正在把瓶子取回来…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    ContentUnavailableView("这封信暂时不在手里",
                                           systemImage: "envelope.open",
                                           description: Text("可以回到海面重新捞一个瓶子。"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle("一起读信")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.current?.id != encounterID {
                loading = true
                _ = await model.loadEncounter(id: encounterID)
                loading = false
            }
            await startOpeningIfNeeded()
        }
        .sheet(isPresented: $showingComposer) {
            if let encounter {
                NavigationStack {
                    DriftBottleComposerView(mode: .message(encounter: encounter)) { record in
                        showingComposer = false
                        if let record { completedRecord = record }
                    }
                }
            }
        }
        .sheet(item: $completedRecord) { record in
            DriftBottleCompletionSheet(record: record) {
                dismiss()
            }
        }
        .sheet(item: $reportTarget) { target in
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("举报这段内容").font(.headline)
                    Text("举报后，这段文字会立刻对你隐藏；管理员会收到待处理记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $reportReason)
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12))
                    Toggle("同时屏蔽这位投稿者", isOn: $blockAfterReport)
                        .font(.footnote)
                    Spacer()
                    HStack {
                        Button("取消") { reportTarget = nil }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("提交举报") {
                            Task {
                                let ok = await model.report(contributionID: target.id,
                                                            reason: reportReason.isEmpty ? "用户举报" : reportReason)
                                if ok && blockAfterReport {
                                    _ = await model.block(contributionID: target.id)
                                }
                                reportTarget = nil
                                reportReason = ""
                                blockAfterReport = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.brandFill)
                        .disabled(model.isWorking)
                    }
                }
                .padding(20)
                .navigationTitle("举报")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("撤回这段文字？", isPresented: Binding(
            get: { withdrawTarget != nil },
            set: { if !$0 { withdrawTarget = nil } }), presenting: withdrawTarget) { target in
            Button("撤回", role: .destructive) {
                Task {
                    _ = await model.withdraw(contributionID: target.id)
                    withdrawTarget = nil
                }
            }
            Button("取消", role: .cancel) { withdrawTarget = nil }
        } message: { _ in
            Text("撤回后，原有位置会显示「这段文字已被收回」，不会破坏其他人的阅读顺序。")
        }
        .confirmationDialog("屏蔽这位投稿者？", isPresented: Binding(
            get: { blockTarget != nil },
            set: { if !$0 { blockTarget = nil } }), presenting: blockTarget) { target in
            Button("屏蔽", role: .destructive) {
                Task {
                    _ = await model.block(contributionID: target.id)
                    blockTarget = nil
                }
            }
            Button("取消", role: .cancel) { blockTarget = nil }
        } message: { _ in
            Text("屏蔽后，这位投稿者的文字会在当前页面隐藏，之后也不会再匹配到包含其内容的瓶子。")
        }
        .confirmationDialog("直接放回这个瓶子？", isPresented: $showingReturnConfirm) {
            Button("放回海面", role: .destructive) {
                Task {
                    if let record = await model.release(contribution: nil) {
                        completedRecord = record
                    }
                }
            }
            Button("再读一会儿", role: .cancel) {}
        } message: {
            Text("直接放回不会增加公开留言。你和 Bot 的这次私人交流仍会留在足迹里。")
        }
    }

    private func header(_ encounter: DriftBottleEncounter) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                BotAvatar(emoji: encounter.botAvatar, color: encounter.botColor, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("和 \(encounter.botName) 一起读").font(.headline)
                    Text(encounter.isActive
                         ? DriftBottlePresentation.remainingText(seconds: encounter.remainingSeconds)
                         : (encounter.endReason == .expired ? "持有时间到了" : "这次相遇已经收好"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if encounter.isActive {
                ProgressView(value: min(1, max(0, 1 - Double(encounter.remainingSeconds) / 86_400)))
                    .tint(Color.brandAccent)
                    .accessibilityLabel("这封瓶子的持有时间")
            }
        }
    }

    private var offlineBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.slash").foregroundStyle(Color.brandAccent)
            Text("现在连不上网络。你和 Bot 的私人交流还在本机；别人写的信件内容等待联网更新，不会显示旧全文。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func letters(_ encounter: DriftBottleEncounter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DriftBottleSectionTitle(title: "瓶子里的文字",
                                    subtitle: "按最初放漂和沿途留下的顺序阅读")
            if encounter.contributions.isEmpty {
                Text("这封信里的公开文字已经被收回。你仍可以和 Bot 聊聊这次相遇。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(encounter.contributions) { item in
                DriftBottleContributionCard(
                    contribution: item,
                    onWithdraw: item.canWithdraw ? { withdrawTarget = item } : nil,
                    onReport: item.canReport ? { reportTarget = item; reportReason = "" } : nil,
                    onBlock: item.canReport ? { blockTarget = item } : nil)
            }
            if encounter.nextCursor != nil {
                Button {
                    Task { await model.loadEarlier() }
                } label: {
                    Label("继续读后面的留言", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .disabled(model.isWorking)
            }
        }
    }

    @ViewBuilder
    private func privateSection(_ encounter: DriftBottleEncounter) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            DriftBottleSectionTitle(title: "只属于你和 \(encounter.botName)",
                                    subtitle: "这里的交流不会公开，也不会写入普通聊天或长期记忆")
            if encounter.botDeleted {
                Text("这位 Bot 已经被删除。过去的私人对话仍然保留，但不能再生成新的回应。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.privateTurns.filter(\.isPrivate)) { turn in
                HStack(alignment: .top, spacing: 10) {
                    if turn.role == .bot {
                        BotAvatar(emoji: encounter.botAvatar, color: encounter.botColor, size: 26)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text(turn.content)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(turn.role == .bot ? Color.brandSoft : Color.sectionFill,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: turn.role == .bot ? .leading : .trailing)
            }
            if encounter.isActive, !encounter.quiet, !encounter.botDeleted,
               !model.privateTurns.contains(where: { $0.kind == .opening }) {
                HStack(spacing: 8) {
                    Button("和它聊聊") {
                        Task { await model.requestOpening() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandFill)
                    Button("安静读一会儿") {
                        Task { await model.requestOpening(quiet: true) }
                    }
                    .accessibilityIdentifier("drift.quiet")
                    .buttonStyle(.bordered)
                }
                .font(.footnote)
            }
            if encounter.isActive, encounter.quiet {
                Text("已经切到安静模式。Bot 不会自动开口，你仍可以主动说话。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !encounter.botDeleted {
                HStack(spacing: 8) {
                    TextField("想和 Bot 说点什么…", text: Binding(
                        get: { model.chatText },
                        set: { model.chatText = $0 }), axis: .vertical)
                        .lineLimit(1...4)
                        .themedFieldBackground()
                        .accessibilityIdentifier("drift.chat.field")
                    Button {
                        let text = model.chatText
                        Task { _ = await model.send(message: text) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandFill)
                    .disabled(model.isWorking || DriftBottlePresentation.validateChat(model.chatText) != nil)
                    .accessibilityIdentifier("drift.chat.send")
                    .accessibilityLabel("发送私人消息")
                }
                HStack {
                    Text("最多 \(DriftBottlePresentation.chatMaxLength) 个字符，只属于这次交流")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(DriftBottlePresentation.characterCount(model.chatText))/\(DriftBottlePresentation.chatMaxLength)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func footer(_ encounter: DriftBottleEncounter) -> some View {
        Divider()
        if encounter.canPublish {
            VStack(alignment: .leading, spacing: 10) {
                DriftBottleSectionTitle(title: "主人决定留下什么",
                                        subtitle: "不留言也没关系。安静读完、直接放回，也是一次完整的相遇")
                HStack(spacing: 10) {
                    Button {
                        showingComposer = true
                    } label: {
                        Label("留下一句", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("drift.leaveMessage")
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandFill)
                    .disabled(model.isWorking)
                    Button {
                        showingReturnConfirm = true
                    } label: {
                        Label("直接放回", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("drift.return")
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(encounter.endReason == .expired ? "这次相遇已经到期" : "这次相遇已经收好")
                    .font(.headline)
                Text("私人交流仍然可以继续，但不能再向这封信追加公开留言。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    DriftBottleRecordDetailView(recordID: "encounter:\(encounter.id)")
                } label: {
                    Label("查看共同回忆", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func offlineReading(_ cached: DriftBottleCachedEncounter) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DriftBottleSectionTitle(title: "和 \(cached.botName) 的私人交流",
                                    subtitle: "信件内容需要联网更新")
            ForEach(cached.turns.filter(\.isPrivate)) { turn in
                Text(turn.content)
                    .font(.subheadline)
                    .padding(12)
                    .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 14))
            }
            Button("重新联网") { Task { await model.load() } }
                .buttonStyle(.bordered)
        }
    }

    private func startOpeningIfNeeded() async {
        guard !didRequestOpening, let encounter, encounter.isActive,
              !encounter.quiet, !encounter.botDeleted, !model.isOffline else { return }
        guard !encounter.turns.contains(where: { $0.kind == .opening }) else { return }
        didRequestOpening = true
        await model.requestOpening()
    }
}
