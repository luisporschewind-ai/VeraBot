import SwiftUI
import VeraBotCore

struct WhackABotGameView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.gameSoundEnabled) private var soundEnabled = true
    @State private var game = WhackABotGame()
    @State private var selectedMode: WhackABotGame.Mode = .normal
    @State private var random = SystemRandomNumberGenerator()
    @State private var clockSample: ContinuousClock.Instant?
    @State private var clockGeneration = UUID()
    @State private var bestScore = 0
    @State private var showingRules = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("游戏模式", selection: $selectedMode) {
                    Text("普通模式").tag(WhackABotGame.Mode.normal)
                    Text("困难模式").tag(WhackABotGame.Mode.hard)
                }
                .pickerStyle(.segmented)
                .disabled(game.phase == .running || game.phase == .paused)
                .accessibilityIdentifier("whack-bot-mode")
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

                Text(game.mode == .normal
                     ? "点中小 Bot +10 分\n空点、漏掉不扣分，放轻松玩。"
                     : "同色 +10 分 · 异色 −10 分 · 最低 0 分\n洞口颜色本局固定，空点、漏掉不扣分。")
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
        .sheet(isPresented: $showingRules) { WhackABotRulesView(mode: game.mode) }
        .hapticFeedback(.impact(weight: .light, intensity: 0.65), trigger: game.hits) { old, new in new > old }
        .hapticFeedback(.error, trigger: game.wrongColorHits) { old, new in new > old }
        .onAppear { loadBestScore() }
        .onChange(of: selectedMode) { _, _ in reset(); loadBestScore() }
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
                WhackABotHole(hole: hole, target: target,
                              holeColor: game.mode == .hard ? game.holeColors[hole] : nil,
                              elapsedMilliseconds: game.elapsedMilliseconds) {
                    guard scenePhase == .active, !showingRules else { return }
                    advanceClock()
                    let previousWrongHits = game.wrongColorHits
                    if game.tap(hole: hole, targetID: target?.id) {
                        saveBestScore()
                        GameSoundPlayer.shared.play(.eat)
                    } else if game.wrongColorHits > previousWrongHits {
                        GameSoundPlayer.shared.play(.keyPress)
                    }
                }
                .disabled(game.phase != .running)
            }
        }
        .padding(14)
        .background(Color.brandSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 26))
        .overlay {
            if game.phase != .running {
                VStack(spacing: 5) {
                    Text(overlayTitle).font(.subheadline.weight(.semibold))
                    Text(overlayDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: 270)
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .opacity(0.45)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.32), lineWidth: 0.8)
                }
                .padding(.horizontal, 12)
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
        case .ready: game.mode == .normal ? "每局 60 秒，点到小 Bot 就得分。" : "每局 60 秒，只点与洞口同色的 Bot。"
        case .running: ""
        case .paused: "倒计时已暂停，准备好后点击继续。"
        case .finished: "得分 \(game.score) · 命中率 \(game.accuracyPercent)%\n命中 \(game.hits) 次 · 本机最佳 \(bestScore)"
        }
    }

    private var bestScoreKey: String {
        let prefix = game.mode == .normal ? "whack_bot_best" : "whack_bot_best_hard"
        return "\(prefix)_\(app.baseURLString)_\(app.userID ?? 0)"
    }
    private func loadBestScore() { bestScore = UserDefaults.standard.integer(forKey: bestScoreKey) }
    private func saveBestScore() {
        // Normal mode preserves its existing live best; hard mode records the final round score.
        guard game.mode == .normal || game.phase == .finished else { return }
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
        game = WhackABotGame(mode: selectedMode, using: &random)
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
            saveBestScore()
            clockSample = nil
            GameSoundPlayer.shared.play(.win)
        }
    }
}

/// The Bot is clipped by the opening, then the near rim is drawn over it.
/// Entry and retreat move through the same ellipse rather than through the cell edge.
private struct WhackABotHole: View {
    let hole: Int
    let target: WhackABotGame.Target?
    let holeColor: BotAvatarColorOption?
    let elapsedMilliseconds: Int
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { holeColor?.color ?? Color(red: 0.22, green: 0.19, blue: 0.28) }
    private var reveal: CGFloat {
        guard let target else { return 0 }
        guard !reduceMotion else { return 1 }
        let entering = Double(elapsedMilliseconds - target.appearedAtMilliseconds) / 140
        let leaving = Double(target.expiresAtMilliseconds - elapsedMilliseconds) / 150
        let progress = min(1, max(0, min(entering, leaving)))
        return CGFloat(progress * progress * (3 - 2 * progress))
    }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { proxy in
                let side = proxy.size.width
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.sectionFill.opacity(0.75))
                    // A colored inner wall with an inset shadow reads as a recess, not a raised ring.
                    Ellipse()
                        .fill(tint.shadow(.inner(color: .black.opacity(0.75), radius: side * 0.055,
                                                 x: 0, y: side * 0.035)))
                        .overlay {
                            Ellipse().fill(LinearGradient(colors: [.black.opacity(0.28), .clear],
                                                          startPoint: .top, endPoint: .bottom))
                        }
                        .overlay { Ellipse().strokeBorder(.black.opacity(0.18), lineWidth: 0.5) }
                        .frame(width: side * 0.84, height: side * 0.28)
                        .position(x: side / 2, y: side * 0.76)
                    ZStack {
                        if let target {
                            RobotAvatarView(action: target.isHit ? .surprise : .idle,
                                            size: side * 0.73, color: target.color.color,
                                            ambient: false, staticPreview: true, motionReduced: true)
                                .allowsHitTesting(false)
                                .position(x: side / 2, y: side * (0.66 + 0.95 * (1 - reveal)))
                        }
                    }
                    .frame(width: side, height: side)
                    .mask(WhackABotOpeningMask())
                    // The near edge overlaps the lower face, establishing depth.
                    WhackABotNearRim()
                        .stroke(LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0.55), tint.opacity(0.12)],
                                               startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 1, lineCap: .butt))
                        .allowsHitTesting(false)
                    if let holeColor {
                        Text(holeColor.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .position(x: side / 2, y: side * 0.96)
                    }
                    if let points = target?.pointsAwarded {
                        Text(points > 0 ? "+10" : "−10")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(points > 0 ? Color.brand : Color.red)
                            .position(x: side / 2, y: side * 0.30)
                    }
                }
                .clipped()
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(WhackABotHoleStyle())
        .animation(reduceMotion ? nil : .linear(duration: 0.05), value: elapsedMilliseconds)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier("whack-bot-hole-\(hole)")
    }

    private var accessibilityDescription: String {
        let opening = "第 \(hole + 1) 个洞" + (holeColor.map { "，洞口\($0.name)" } ?? "")
        guard let target else { return opening + "，空洞" }
        if let points = target.pointsAwarded { return opening + (points > 0 ? "，已得分" : "，已扣分") }
        return opening + "，\(target.color.name)小 Bot 探头"
    }
}

/// Disabled holes remain visually solid; pause should stop input without making the Bot transparent.
private struct WhackABotHoleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

private struct WhackABotOpeningMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: 0, y: 0, width: rect.width, height: rect.height * 0.76))
        path.addEllipse(in: CGRect(x: rect.width * 0.08, y: rect.height * 0.62,
                                   width: rect.width * 0.84, height: rect.height * 0.28))
        return path
    }
}

private struct WhackABotNearRim: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.08, y: rect.height * 0.76))
        path.addCurve(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.76),
                      control1: CGPoint(x: rect.width * 0.08, y: rect.height * 0.947),
                      control2: CGPoint(x: rect.width * 0.92, y: rect.height * 0.947))
        return path
    }
}

private struct WhackABotRulesView: View {
    let mode: WhackABotGame.Mode
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("怎样玩") {
                    Text("每局 60 秒，小 Bot 会从九个洞口随机探头，每次出现从全部 Bot 配色中随机选色。同一次探头只判定一次。")
                    if mode == .normal {
                        Text("普通模式：点中任何颜色的小 Bot 都加 10 分。")
                    } else {
                        Text("困难模式：洞口每局开始时随机配色，局内固定。只有 Bot 与所在洞口颜色相同才加 10 分；点中异色 Bot 扣 10 分，最低 0 分。洞口下方标有颜色名。")
                    }
                    Text("每过 20 秒节奏加快，同时探头的小 Bot 最多为 1、2、3 个。空点和漏掉都不扣分。")
                    Text("命中率 = 得分命中次数 ÷ 点击次数；空点、重复点已判定的 Bot 均不扣分，但计入点击次数。普通、困难模式分别保存本机最佳，困难模式按本局结束时的得分记录；一局结束后可以切换模式。")
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
