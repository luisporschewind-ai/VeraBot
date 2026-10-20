import SwiftUI
import VeraBotCore

struct WhackABotGameView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.gameSoundEnabled) private var soundEnabled = true
    @State private var game = WhackABotGame()
    @State private var random = SystemRandomNumberGenerator()
    @State private var clockSample: ContinuousClock.Instant?
    @State private var clockGeneration = UUID()
    @State private var bestScore = 0
    @State private var showingRules = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    statistic("得分", value: "\(game.score)")
                    Spacer()
                    statistic("剩余时间", value: "\(game.remainingSeconds) 秒")
                    Spacer()
                    statistic("本机最佳", value: "\(bestScore)")
                }

                HStack {
                    Label("九宫格 · 小 Bot", systemImage: "sparkles")
                    Spacer()
                    Text("节奏 \(game.level) · 命中率 \(game.accuracyPercent)%")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                board

                HStack(spacing: 12) {
                    Button(action: primaryAction) {
                        Label(primaryTitle, systemImage: game.phase == .running ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(GameButtonStyle(tone: .primary))
                    .accessibilityIdentifier("whack-bot-primary")
                    Button {
                        reset()
                        begin()
                    } label: {
                        Label("重开", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(GameButtonStyle(tone: .secondary))
                    .disabled(game.phase == .ready)
                    .accessibilityIdentifier("whack-bot-restart")
                }

                Text("点中小 Bot +10 分\n空点、漏掉不扣分，放轻松玩。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle("打地鼠 · 小 Bot 版")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    soundEnabled.toggle()
                } label: {
                    Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .accessibilityLabel(soundEnabled ? "关闭游戏音效" : "开启游戏音效")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("玩法") { pause(); showingRules = true }
            }
        }
        .sheet(isPresented: $showingRules) { WhackABotRulesView() }
        .hapticFeedback(.impact(weight: .light, intensity: 0.65), trigger: game.hits) { old, new in new > old }
        .onAppear { loadBestScore() }
        .onChange(of: soundEnabled) { _, enabled in
            GameSoundPlayer.shared.setEnabled(enabled)
            if game.phase != .running { GameSoundPlayer.shared.stopAll() }
        }
        .onChange(of: app.sessionGeneration) { _, _ in reset(); loadBestScore() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { pause() } }
        .onDisappear { pause() }
        .task(id: clockGeneration) {
            let generation = clockGeneration
            while !Task.isCancelled, game.phase == .running {
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
                guard !Task.isCancelled, generation == clockGeneration,
                      scenePhase == .active, game.phase == .running else { return }
                advanceClock()
            }
        }
    }

    private var board: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
            ForEach(0..<9, id: \.self) { hole in
                let target = game.targets.first { $0.hole == hole }
                WhackABotHole(hole: hole, target: target) {
                    guard scenePhase == .active, !showingRules else { return }
                    advanceClock()
                    if game.tap(hole: hole, targetID: target?.id) {
                        saveBestScore()
                        GameSoundPlayer.shared.play(.eat)
                    }
                }
                .disabled(game.phase != .running)
            }
        }
        .padding(14)
        .background(Color.brandSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 26))
        .overlay {
            if game.phase != .running {
                VStack(spacing: 10) {
                    Image(systemName: game.phase == .finished ? "flag.checkered" : "hand.tap")
                        .font(.title2)
                        .foregroundStyle(Color.brand)
                    Text(overlayTitle).font(.headline)
                    Text(overlayDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .padding(24)
                .allowsHitTesting(false)
                .accessibilityIdentifier("whack-bot-status")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: game.phase)
    }

    private func statistic(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(Color.brand)
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryTitle: String {
        switch game.phase {
        case .ready: "开始游戏"
        case .running: "暂停"
        case .paused: "继续"
        case .finished: "再玩一局"
        }
    }

    private var overlayTitle: String {
        switch game.phase {
        case .ready: "和小 Bot 玩捉迷藏"
        case .running: ""
        case .paused: "休息一下"
        case .finished: "这一局完成啦"
        }
    }

    private var overlayDetail: String {
        switch game.phase {
        case .ready: "小 Bot 会从洞里探头，\n试着点到它吧！每局 60 秒。"
        case .running: ""
        case .paused: "倒计时已暂停，\n准备好后点击继续。"
        case .finished: "得分 \(game.score) · 命中率 \(game.accuracyPercent)%\n命中 \(game.hits) 次 · 本机最佳 \(bestScore)"
        }
    }

    private var bestScoreKey: String { "whack_bot_best_\(app.baseURLString)_\(app.userID ?? 0)" }
    private func loadBestScore() { bestScore = UserDefaults.standard.integer(forKey: bestScoreKey) }
    private func saveBestScore() {
        guard game.score > bestScore else { return }
        bestScore = game.score
        UserDefaults.standard.set(bestScore, forKey: bestScoreKey)
    }

    private func primaryAction() {
        guard scenePhase == .active else { return }
        switch game.phase {
        case .running: pause(withSound: true)
        case .ready, .paused: begin()
        case .finished: reset(); begin()
        }
    }

    private func begin() {
        guard scenePhase == .active else { return }
        let resuming = game.phase == .paused
        game.start()
        clockSample = .now
        clockGeneration = UUID()
        GameSoundPlayer.shared.activate()
        GameSoundPlayer.shared.play(resuming ? .resume : .start)
    }

    private func pause(withSound: Bool = false) {
        if game.phase == .running { advanceClock(); game.pause() }
        clockSample = nil
        clockGeneration = UUID()
        if withSound { GameSoundPlayer.shared.pauseWithConfirmation() }
        else { GameSoundPlayer.shared.stopAll() }
    }

    private func reset() {
        GameSoundPlayer.shared.stopAll()
        game = WhackABotGame()
        clockSample = nil
        clockGeneration = UUID()
    }

    private func advanceClock() {
        guard game.phase == .running, let sample = clockSample else { return }
        let duration = sample.duration(to: .now).components
        let milliseconds = Int(min(duration.seconds, 60)) * 1_000 + Int(duration.attoseconds / 1_000_000_000_000_000)
        guard milliseconds > 0 else { return }
        clockSample = sample.advanced(by: .milliseconds(milliseconds))
        game.advance(milliseconds: milliseconds, using: &random)
        if game.phase == .finished {
            clockSample = nil
            GameSoundPlayer.shared.play(.win)
        }
    }
}

private struct WhackABotHole: View {
    let hole: Int
    let target: WhackABotGame.Target?
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var botColor: Color { [RobotAvatarTone.violet.color, RobotAvatarTone.blue.color, RobotAvatarTone.graphite.color][hole % 3] }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { proxy in
                let side = proxy.size.width
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.sectionFill.opacity(0.75))
                    Ellipse()
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: side * 0.82, height: side * 0.27)
                        .position(x: side / 2, y: side * 0.73)
                    if let target {
                        RobotAvatarView(action: target.isHit ? .surprise : .idle,
                                        size: side * 0.73, color: botColor,
                                        // Sample the representative eyes immediately; the full surprise has a 500 ms lead-in.
                                        ambient: false, staticPreview: true, motionReduced: true)
                            .allowsHitTesting(false)
                            .scaleEffect(target.isHit ? 0.82 : 1)
                            .offset(y: target.isHit && !reduceMotion ? side * 0.12 : 0)
                            .position(x: side / 2, y: side * 0.43)
                            .id(target.id)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        if target.isHit {
                            Text("+10")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(Color.brand)
                                .position(x: side / 2, y: side * 0.16)
                                .transition(.opacity)
                        }
                    }
                }
                .clipped()
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: target)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(hole + 1) 个洞，\(target == nil ? "空洞" : target?.isHit == true ? "已点中" : "小 Bot 探头")")
        .accessibilityIdentifier("whack-bot-hole-\(hole)")
    }
}

private struct WhackABotRulesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("怎样玩") {
                    Text("每局 60 秒，小 Bot 会从九个洞口随机探头。点中一次加 10 分，同一个小 Bot 只能计分一次。")
                    Text("每过 20 秒节奏加快，同时探头的小 Bot 最多为 1、2、3 个。空点和漏掉都不扣分。")
                    Text("命中率 = 命中次数 ÷ 点击次数；重复点已命中的 Bot 也算空点。")
                }
                Section("随时休息") {
                    Text("可暂停、继续或重开；打开玩法、离开页面、切到后台或锁屏会暂停，回来后手动继续。")
                    Text("本机最佳按当前账号与服务器分别保存。本局进度在关闭游戏页面后不保留。游戏支持离线游玩。")
                }
            }
            .navigationTitle("打地鼠玩法")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
