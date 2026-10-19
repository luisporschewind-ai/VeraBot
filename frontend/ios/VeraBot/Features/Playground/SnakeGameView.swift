import SwiftUI
import VeraBotCore

struct SnakeGameView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var game = SnakeGame()
    @State private var bestScore = 0
    @State private var clockGeneration = UUID()
    @State private var showingRules = false
    @AppStorage(SettingsKeys.gameSoundEnabled) private var gameSoundEnabled = true

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                statistic("得分", value: game.score)
                Spacer()
                statistic("本机最佳", value: bestScore)
                Spacer()
                statistic("长度", value: game.snake.count)
            }

            HStack {
                Text("吃到食物 +10 分")
                Spacer()
                Text("速度 \(game.level)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                SnakeBoard(game: game)
                    .frame(width: side, height: side)
                    .overlay {
                        if game.phase != .running {
                            VStack(spacing: 7) {
                                Text(overlayTitle).font(.headline)
                                Text(overlayDetail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .padding(12)
                            .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 16).onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard max(abs(dx), abs(dy)) >= 16 else { return }
                        let accepted = game.turn(abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up))
                        if accepted { GameSoundPlayer.shared.play(.keyPress) }
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 12) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: game.phase == .running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(GameButtonStyle(tone: .primary))
                .accessibilityIdentifier("snake-primary-action")

                Button(action: restart) {
                    Label("重开", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(GameButtonStyle(tone: .secondary))
                .disabled(game.phase == .ready)
                .accessibilityIdentifier("snake-restart")
            }
        }
        .padding(18)
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                GameDpad(
                    onUp: { game.turn(.up); GameSoundPlayer.shared.play(.keyPress) },
                    onDown: { game.turn(.down); GameSoundPlayer.shared.play(.keyPress) },
                    onLeft: { game.turn(.left); GameSoundPlayer.shared.play(.keyPress) },
                    onRight: { game.turn(.right); GameSoundPlayer.shared.play(.keyPress) },
                    repeatEnabled: false
                )
                Text("滑动棋盘或使用方向键 · 不能直接掉头")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .disabled(game.phase != .running)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .themedPageBackground()
        .navigationTitle("贪吃蛇")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    gameSoundEnabled.toggle()
                    GameSoundPlayer.shared.setEnabled(gameSoundEnabled)
                } label: {
                    Image(systemName: gameSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .accessibilityLabel(gameSoundEnabled ? "关闭游戏音效" : "开启游戏音效")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("玩法") { pause(); showingRules = true }
            }
        }
        .sheet(isPresented: $showingRules) {
            NavigationStack {
                List {
                    Section("怎样玩") {
                        Text("点击开始后，滑动棋盘或按方向键转向；每一步只能转向一次，不能直接反向。")
                        Text("每吃一颗食物增加 10 分、增长一格；每吃 4 颗提高一档速度。")
                        Text("碰到边界或自己的身体会结束；占满棋盘即为获胜。")
                    }
                    Section("随时休息") {
                        Text("可随时暂停。离开页面、切换 App 或锁屏会自动暂停，回来后点击继续。")
                        Text("最佳分数仅保存在当前账号和服务器对应的本机记录中。本局进度在页面关闭后不保留。")
                    }
                }
                .navigationTitle("贪吃蛇玩法")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingRules = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { loadBestScore(); GameSoundPlayer.shared.activate() }
        .onChange(of: gameSoundEnabled) { _, enabled in GameSoundPlayer.shared.setEnabled(enabled) }
        .onChange(of: app.sessionGeneration) { _, _ in GameSoundPlayer.shared.stopAll(); restart(); loadBestScore() }
        .onChange(of: game.score) { _, score in
            guard score > bestScore else { return }
            bestScore = score
            UserDefaults.standard.set(score, forKey: bestScoreKey)
        }
        .onChange(of: game.soundEventsVersion) { _, _ in
            let events = game.drainSoundEvents()
            if scenePhase == .active && game.phase != .paused {
                for event in events { GameSoundPlayer.shared.play(event) }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { pause(); GameSoundPlayer.shared.stopAll() } }
        .onDisappear { pause(); GameSoundPlayer.shared.stopAll() }
        .task(id: clockGeneration) {
            let generation = clockGeneration
            while !Task.isCancelled, game.phase == .running {
                do { try await Task.sleep(for: .milliseconds(game.tickIntervalMilliseconds)) }
                catch { return }
                guard !Task.isCancelled, clockGeneration == generation,
                      scenePhase == .active, game.phase == .running else { return }
                game.tick()
            }
        }
    }

    private func statistic(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title2.bold().monospacedDigit()).foregroundStyle(Color.brand)
        }
    }

    private var primaryTitle: String {
        switch game.phase {
        case .ready: "开始游戏"
        case .running: "暂停"
        case .paused: "继续"
        case .lost, .won: "再玩一局"
        }
    }

    private var overlayTitle: String {
        switch game.phase {
        case .ready: "准备好就出发"
        case .running: ""
        case .paused: "游戏已暂停"
        case .lost: "这一局结束啦"
        case .won: "整个棋盘都走遍了！"
        }
    }

    private var overlayDetail: String {
        switch game.phase {
        case .ready: "吃食物、慢慢长大，留意边界和身体。"
        case .running: ""
        case .paused: "准备好后，点击继续。"
        case .lost: "\(game.endReason == .wall ? "碰到边界了" : "碰到自己的身体了") · 本局 \(game.score) 分"
        case .won: "本局 \(game.score) 分，恭喜完成！"
        }
    }

    private var bestScoreKey: String { "snake_best_\(app.baseURLString)_\(app.userID ?? 0)" }
    private func loadBestScore() { bestScore = UserDefaults.standard.integer(forKey: bestScoreKey) }

    private func primaryAction() {
        switch game.phase {
        case .running:
            game.pause(); clockGeneration = UUID()
            GameSoundPlayer.shared.pauseWithConfirmation()
        case .ready:
            GameSoundPlayer.shared.activate()
            game.start(); clockGeneration = UUID()
            GameSoundPlayer.shared.play(.start)
        case .paused:
            GameSoundPlayer.shared.activate()
            game.start(); clockGeneration = UUID()
            GameSoundPlayer.shared.play(.resume)
        case .lost, .won:
            restart()
            GameSoundPlayer.shared.activate()
            game.start(); clockGeneration = UUID()
            GameSoundPlayer.shared.play(.start)
        }
    }

    private func pause() { game.pause(); clockGeneration = UUID(); GameSoundPlayer.shared.stopAll() }
    private func restart() { game = SnakeGame(); clockGeneration = UUID() }
}

private struct SnakeBoard: View {
    let game: SnakeGame

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 7
            let cell = (size.width - inset * 2) / CGFloat(game.width)
            var grid = Path()
            for index in 0...game.width {
                let x = inset + CGFloat(index) * cell
                grid.move(to: CGPoint(x: x, y: inset))
                grid.addLine(to: CGPoint(x: x, y: size.height - inset))
            }
            for index in 0...game.height {
                let y = inset + CGFloat(index) * cell
                grid.move(to: CGPoint(x: inset, y: y))
                grid.addLine(to: CGPoint(x: size.width - inset, y: y))
            }
            context.stroke(grid, with: .color(.primary.opacity(0.045)), lineWidth: 0.5)

            for (index, part) in game.snake.enumerated() {
                let rect = CGRect(x: inset + CGFloat(part.column) * cell + 1,
                                  y: inset + CGFloat(part.row) * cell + 1, width: cell - 2, height: cell - 2)
                context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.23),
                             with: .color(Color.brand.opacity(index == 0 ? 1 : 0.65)))
                if index == 0 {
                    let horizontal = game.direction == .left || game.direction == .right
                    let forward: CGFloat = game.direction == .up || game.direction == .left ? -0.17 : 0.17
                    for side in [CGFloat(-0.19), CGFloat(0.19)] {
                        let center = CGPoint(x: rect.midX + cell * (horizontal ? forward : side),
                                             y: rect.midY + cell * (horizontal ? side : forward))
                        let eye = CGRect(x: center.x - cell * 0.065, y: center.y - cell * 0.065,
                                         width: cell * 0.13, height: cell * 0.13)
                        context.fill(Path(ellipseIn: eye), with: .color(.white))
                    }
                }
            }

            if let food = game.food {
                let rect = CGRect(x: inset + CGFloat(food.column) * cell + cell * 0.16,
                                  y: inset + CGFloat(food.row) * cell + cell * 0.16,
                                  width: cell * 0.68, height: cell * 0.68)
                context.fill(Path(ellipseIn: rect), with: .color(.orange))
            }
        }
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1), lineWidth: 1) }
        .accessibilityLabel("贪吃蛇棋盘，得分 \(game.score)，长度 \(game.snake.count)")
        .accessibilityIdentifier("snake-board")
    }
}
