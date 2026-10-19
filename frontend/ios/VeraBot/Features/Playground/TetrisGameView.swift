import SwiftUI
import VeraBotCore
import VeraBotNetworking
import VeraBotData

struct TetrisGameView: View {
  @State private var game = TetrisGame(ruleVersion: "vera-tetris-2")

  @Environment(AppState.self) private var app
  @Environment(\.scenePhase) private var scenePhase
  @State private var companion = TetrisCompanionModel()
  @State private var takeover = TetrisSessionModel(clientID: TetrisSessionCache.installationClientID())
  @State private var showingRecoveryMenu = false
  @State private var showingEndConfirmation = false
  @State private var separateLocal: TetrisState?
  @State private var remoteBaseline = true
  @State private var showingConversation = false
  @State private var showingPartners = false
  @State private var showingMenu = false
  @State private var showingRules = false
  @State private var showingRestartConfirmation = false
  @State private var inputEpoch = 0
  @State private var countdown = TetrisCountdownState()
  @State private var countdownTask: Task<Void, Never>?
  @AppStorage(SettingsKeys.hapticsEnabled) private var hapticsEnabled = true
  @AppStorage(SettingsKeys.gameSoundEnabled) private var gameSoundEnabled = true

  private var sessionContent: some View {
    presentedContent
      .onAppear { GameSoundPlayer.shared.activate() }
      .onChange(of: app.sessionGeneration) { _, _ in
        pauseGame()
        takeover.clearAccount()
        separateLocal = nil
        game = TetrisGame(ruleVersion: "vera-tetris-2")
      }
      .task(id: "\(app.sessionGeneration):\(app.baseURLString):\(app.userID ?? 0)") {
        remoteBaseline = true
        if let userID = app.userID {
          await takeover.configure(api: app.api, server: app.baseURLString, userID: userID)
        } else { takeover.clearAccount() }
      }
      .onChange(of: takeover.displaySnapshot) { _, state in
        guard let state, let restored = try? TetrisGame(restoring: state) else { return }
        cancelInput()
        game = restored
        if remoteBaseline || takeover.remote?.snapshotFallback == true {
          companion.synchronize(lines: state.lines)
          remoteBaseline = false
        } else if scenePhase == .active {
          companion.observe(snapshot(event: game.isGameOver ? "end" : "clear"), ended: game.isGameOver, app: app)
        }
      }
      .onChange(of: takeover.remote?.botID) { _, _ in alignRemoteCompanion() }
      .onChange(of: takeover.canRunLocal) { _, allowed in if !allowed { cancelInput() } }
      .onChange(of: gameSoundEnabled) { _, enabled in GameSoundPlayer.shared.setEnabled(enabled) }
      .task(id: app.sessionGeneration) {
        companion.newRound()
        companion.selected = nil
        companion.bots = []
        await companion.load(app: app)
        guard !Task.isCancelled else { return }
        alignRemoteCompanion()
        if game.state.phase == .running {
          companion.send(snapshot(event: "start"), automatic: true, app: app)
        }
      }
  }

  private var observedContent: some View {
    sessionContent
      .onChange(of: game.soundTick) { _, _ in
        let events = game.drainSounds()
        if !game.isPaused && scenePhase == .active {
          for event in events { GameSoundPlayer.shared.play(event) }
        }
      }
      .onChange(of: game.isPaused) { _, paused in
        if paused {
          inputEpoch += 1
          companion.flushPending()
        }
      }
      .onChange(of: game.isGameOver) { _, ended in if ended { cancelInput() } }
      .onChange(of: scenePhase) { _, phase in
        if phase != .active {
          pauseGame()
          companion.stop()
          remoteBaseline = true
          takeover.setActive(false)
          saveLocal()
        } else {
          remoteBaseline = true
          takeover.setActive(true)
        }
      }
      .onDisappear {
        pauseGame()
        companion.stop()
        saveLocal()
        takeover.stopObserving()
      }
  }

  var body: some View {
    observedContent
      .sheet(isPresented: $showingConversation) { conversationContent }
      .sheet(isPresented: $showingPartners) { partnersContent }
      .task(id: "\(game.state.phase):\(takeover.canRunLocal)") {
        guard takeover.canRunLocal else { return }
        guard game.state.phase == .running || game.state.phase == .clearing else { return }
        var previous = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(50))
          guard !Task.isCancelled, takeover.canRunLocal else { return }
          let current = ProcessInfo.processInfo.systemUptime
          let elapsed = Int((current - previous) * 1000)
          previous = current
          // A long suspended UI frame pauses instead of delivering a punitive catch-up burst.
          guard elapsed <= 500 else {
            pauseGame()
            return
          }
          advance(milliseconds: elapsed)
        }
      }
  }

  private var presentedContent: some View {
    mainContent
      .padding(18)
      .frame(maxWidth: 480)
      .frame(maxWidth: .infinity)
      .safeAreaInset(edge: .bottom, spacing: 0) { handheldControls }
      .themedPageBackground()
      .navigationTitle("俄罗斯方块")
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
      }
      .confirmationDialog("游戏菜单", isPresented: $showingMenu, titleVisibility: .visible) {
        Button("玩法说明") { showingRules = true }
        Button(gameSoundEnabled ? "关闭游戏音效" : "开启游戏音效") {
          gameSoundEnabled.toggle()
          GameSoundPlayer.shared.setEnabled(gameSoundEnabled)
        }
        Button(hapticsEnabled ? "关闭触感反馈" : "开启触感反馈") { hapticsEnabled.toggle() }
        Button("换伙伴", action: openPartners)
        Button("聊聊", action: openConversation)
        if takeover.canRunLocal {
          Button("重新开始", role: .destructive) { showingRestartConfirmation = true }
        } else {
          Button("另开本地局", action: startSeparateRound)
          if takeover.canCommand { Button("结束代玩", role: .destructive) { showingEndConfirmation = true } }
        }
        Button("取消", role: .cancel) {}
      } message: {
        Text("重新开始会清空本局分数。")
      }
      .alert("重新开始这一局？", isPresented: $showingRestartConfirmation) {
        Button("取消", role: .cancel) {}
        Button("重新开始", role: .destructive, action: restart)
      } message: {
        Text("当前棋盘和本局分数将被清空。")
      }
      .confirmationDialog("交接状态待确认", isPresented: $showingRecoveryMenu, titleVisibility: .visible) {
        Button("重试查询") { Task { await takeover.refresh() } }
        Button("另开本地局", action: startSeparateRound)
        Button("玩法说明") { showingRules = true }
        Button("取消", role: .cancel) {}
      } message: { Text("原代玩局会保留，确认交接前本局不恢复操作。") }
      .alert("结束这局代玩？", isPresented: $showingEndConfirmation) {
        Button("取消", role: .cancel) {}
        Button("结束本局", role: .destructive) { Task { await takeover.endRound() } }
      } message: { Text("结束后不会自动开启下一局。") }
      .sheet(isPresented: $showingRules) { rulesContent }
  }

  private var handheldControls: some View {
    VStack(spacing: 10) {
      HStack(alignment: .center) {
        GameDpad(
          onUp: nil,
          onDown: {
            apply(.softDrop)
            GameSoundPlayer.shared.play(.keyPress)
          },
          onLeft: {
            apply(.moveLeft)
            GameSoundPlayer.shared.play(.keyPress)
          },
          onRight: {
            apply(.moveRight)
            GameSoundPlayer.shared.play(.keyPress)
          },
          repeatEnabled: true,
          inputEpoch: inputEpoch
        )
        .disabled(!takeover.canRunLocal || game.state.phase != .running || countdown.remaining != nil)

        Spacer()

        GameFaceCluster(
          onA: {
            apply(.rotateClockwise)
            GameSoundPlayer.shared.play(.keyPress)
          },
          onB: { apply(.hardDrop) }  // 硬降只播落地声，不叠加按键声
        )
        .disabled(!takeover.canRunLocal || game.state.phase != .running || countdown.remaining != nil)
      }

      HStack(spacing: 14) {
        GamePillKey(
          title: startTitle,
          systemImage: game.isPaused || game.state.phase == .ready ? "play.fill" : "pause.fill",
          action: togglePause
        )
        .disabled(game.isGameOver || (!takeover.canRunLocal && !takeover.canCommand))
        GamePillKey(title: "菜单", systemImage: "ellipsis", action: openMenu)
      }
      .frame(maxWidth: .infinity)

      Text("十字键移动 · A 旋转 · B 直接落下")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 18)
    .padding(.top, 8)
    .padding(.bottom, 6)
    .background(.ultraThinMaterial)

  }

  private var rulesContent: some View {
    NavigationStack {
      List {
        Section("掌机操作") {
          Text("十字键左右移动，向下缓降。上方向不绑定操作。")
          Text("A 顺时针旋转，B 直接落下。按住方向可连续操作。")
          Text("暂停或打开菜单后游戏停止，继续前有三秒倒数。")
          Text("每组七种方块各一次，淡轮廓显示直接落下的位置。触地后有短暂微调时间，B 会立即落定。")
        }
        Section("计分") {
          Text("消除 1 / 2 / 3 / 4 行分别获得 100 / 300 / 500 / 800 分。")
          Text("缓降每格 1 分，直接落下每格 2 分；每消除 10 行逐渐加速。")
        }
      }
      .navigationTitle("玩法说明").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("完成") { showingRules = false } }
      }
    }.presentationDetents([.medium, .large])

  }

  private var conversationContent: some View {
    TetrisCompanionConversation(
      model: companion,
      summary: "\(roundEnded ? "这一局结束了" : "游戏已暂停") · \(game.score) 分 · 消除 \(game.lines) 行",
      onSend: { message in
        var request = snapshot(event: "chat")
        request.message = message
        companion.send(request, automatic: false, app: app)
      }, onContinue: { showingConversation = false }
    )
    .presentationDetents([.medium, .large])

  }

  private var partnersContent: some View {
    NavigationStack {
      List(companion.bots) { bot in
        Button {
          let session = app.sessionGeneration
          Task {
            if !takeover.canRunLocal, takeover.canCommand {
              await takeover.changeBot(id: bot.id)
              guard app.isCurrentSession(session), takeover.phase == .botPaused,
                    takeover.remote?.botID == bot.id else { return }
            }
            guard app.isCurrentSession(session) else { return }
            companion.choose(bot, app: app)
            showingPartners = false
          }
        } label: {
          HStack {
            LiveBotAvatar(
              botID: bot.id, emoji: bot.avatar, color: bot.color,
              hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt,
              size: 40, appearance: bot.supportedAppearance
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            Text(bot.name).foregroundStyle(.primary)
            Spacer()
            if companion.selected?.id == bot.id {
              Image(systemName: "checkmark").foregroundStyle(Color.brand)
            }
          }
        }
      }
      .navigationTitle("邀请一个伙伴")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("完成") { showingPartners = false } }
      }
    }.presentationDetents([.medium, .large])

  }

  private var mainContent: some View {
    VStack(spacing: 12) {
      scoreHeader

      GeometryReader { proxy in
        let companionWidth = min(112, max(96, proxy.size.width * 0.32))
        let boardWidth = max(
          1, min(290, proxy.size.width - companionWidth - 12, proxy.size.height / 2))
        boardArea(width: boardWidth, companionWidth: companionWidth)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }

      takeoverStatus
        .frame(minHeight: 44)

    }
  }

  private var scoreHeader: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 4) {
        Text(roundEnded ? "这一局结束啦" : "方块落下，慢慢找位置")
          .font(.headline)
        Text(contributionText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        Text("\(game.score)")
          .font(.title2.bold().monospacedDigit())
          .foregroundStyle(Color.brand)
        Text("\(game.lines) 行")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func boardArea(width boardWidth: CGFloat, companionWidth: CGFloat) -> some View {
    HStack(spacing: 12) {
      TetrisBoard(game: game, countdown: countdown.remaining, ended: roundEnded)
        .frame(width: boardWidth, height: boardWidth * 2)
      VStack(spacing: 8) {
        Text("下一个")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        TetrisNextPiece(kind: game.nextKind)
          .frame(width: 74, height: 74)
        Spacer(minLength: 8)

        TetrisCompanionPresence(
          model: companion, compact: boardWidth * 2 < 420,
          activity: takeover.canRunLocal ? nil : (takeover.phase == .botRunning ? "正在替你玩" : "在这里等你"),
          onTalk: openConversation,
          onChoose: openPartners,
          onQuiet: { companion.setQuiet(!companion.quiet) },
          onRetry: { Task { await companion.load(app: app) } })
      }
      .frame(width: companionWidth)
      .frame(maxHeight: .infinity, alignment: .top)
    }
    .frame(maxWidth: .infinity)
    .frame(height: boardWidth * 2)
  }

  private func alignRemoteCompanion() {
    guard !takeover.canRunLocal, let botID = takeover.remote?.botID,
          companion.selected?.id != botID,
          let bot = companion.bots.first(where: { $0.id == botID }) else { return }
    companion.choose(bot, app: app)
  }

  private var roundEnded: Bool {
    game.isGameOver || (!takeover.control.viewingSeparateLocal && takeover.phase == .ended)
  }

  private var startTitle: String {
    if !takeover.canRunLocal { return takeover.phase == .botPaused ? "继续代玩" : "暂停代玩" }
    return game.state.phase == .ready ? "开始" : (countdown.remaining != nil ? "暂停" : (game.isPaused ? "继续" : "暂停"))
  }

  private var contributionText: String {
    guard !takeover.control.viewingSeparateLocal, let total = takeover.remote?.contribution else {
      return "消除整行得分，速度会逐渐加快。"
    }
    let extra = takeover.phase == .returned ? max(0, game.score - (takeover.remote?.latestSnapshot.score ?? game.score)) : 0
    return "你：\(total.playerScore + extra) 分 · Bot：\(total.botScore) 分"
  }

  private var takeoverStatus: some View {
    HStack(spacing: 8) {
      Text(takeover.message ?? takeover.statusText)
        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
      Spacer(minLength: 0)
      if takeover.control.viewingSeparateLocal {
        Button("查看代玩") {
          pauseGame()
          separateLocal = game.state
          remoteBaseline = true
          takeover.watchRemote()
          if let state = takeover.displaySnapshot, let restored = try? TetrisGame(restoring: state) { game = restored }
          Task { await takeover.refresh() }
        }
      } else if takeover.canRunLocal {
        if game.isGameOver {
          Button("本局回顾", action: reviewRound)
        } else if takeover.capabilities?.available != true || takeover.capabilities?.compatible != true {
          Button("检查代玩") { Task { await takeover.refresh() } }
        } else {
          Button("交给 Bot", action: handoff)
            .disabled(!takeover.canHandoff || companion.selected == nil || game.state.phase == .ready)
        }
      } else if takeover.phase == .pending || takeover.phase == .recoveryRequired {
        Button("重试") { Task { await takeover.refresh() } }
      } else if takeover.phase == .ended {
        Button("新一局", action: restart)
      } else {
        Button("我来玩") { Task { await takeover.reclaim() } }
          .disabled(!takeover.canCommand)
      }
    }
    .font(.footnote.weight(.medium))
    .padding(.horizontal, 10)
    .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 12))
    .accessibilityIdentifier("tetris-takeover-status")
  }

  private func handoff() {
    guard takeover.canHandoff, let bot = companion.selected else { return }
    pauseGame()
    remoteBaseline = true
    let state = game.state
    Task { await takeover.handoff(snapshot: state, botID: bot.id) }
  }

  private func preparePanel(_ present: @escaping () -> Void) {
    pauseGame()
    let session = app.sessionGeneration
    Task {
      guard await takeover.pauseForPanel(), app.isCurrentSession(session) else {
        if app.isCurrentSession(session) { showingRecoveryMenu = true }
        return
      }
      present()
    }
  }

  private func openPartners() { preparePanel { showingPartners = true } }

  private func openConversation() {
    preparePanel {
      companion.prepareConversation()
      showingConversation = true
    }
  }

  private func saveLocal() {
    let state = game.state
    let scope = takeover.cacheScope
    let generation = takeover.control.generation
    Task { await takeover.persistLocal(state, expectedScope: scope, expectedGeneration: generation) }
  }

  private func startSeparateRound() {
    cancelInput()
    takeover.startSeparateLocalRound()
    game = (separateLocal.flatMap { try? TetrisGame(restoring: $0) }) ?? TetrisGame(ruleVersion: "vera-tetris-2")
    companion.newRound()
  }

  private func cancelInput() {
    inputEpoch += 1
    countdown.cancel()
    countdownTask?.cancel()
    countdownTask = nil
  }

  private func pauseGame(confirmation: Bool = false) {
    cancelInput()
    if takeover.canRunLocal { apply(.pause); saveLocal() }
    if confirmation {
      GameSoundPlayer.shared.pauseWithConfirmation()
    } else {
      GameSoundPlayer.shared.stopAll()
    }
  }

  private func openMenu() {
    preparePanel { showingMenu = true }
  }

  private func togglePause() {
    if !takeover.canRunLocal {
      guard takeover.canCommand else { return }
      Task {
        if takeover.phase == .botPaused { await takeover.resumeBot() }
        else if takeover.phase == .botRunning { await takeover.pauseBot() }
      }
      return
    }
    guard !game.isGameOver else { return }
    if game.state.phase == .ready {
      cancelInput()
      GameSoundPlayer.shared.activate()
      apply(.start)
      companion.send(snapshot(event: "start"), automatic: true, app: app)
      GameSoundPlayer.shared.play(.start)
      return
    }
    if countdown.remaining != nil {
      pauseGame()
      return
    }
    guard game.isPaused else {
      pauseGame(confirmation: true)
      return
    }
    let token = countdown.start()
    countdownTask = Task { @MainActor in
      for _ in 0..<3 {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, takeover.canRunLocal, countdown.generation == token else { return }
        if countdown.tick(generation: token) {
          GameSoundPlayer.shared.activate()
          apply(.resume)
          GameSoundPlayer.shared.play(.resume)
        }
      }
    }
  }

  private func restart() {
    cancelInput()
    let session = app.sessionGeneration
    Task {
      await takeover.newLocalRound()
      guard app.isCurrentSession(session) else { return }
      game = TetrisGame(ruleVersion: "vera-tetris-2")
      separateLocal = nil
      companion.newRound()
    }
  }

  private func apply(_ action: TetrisAction) {
    guard takeover.canRunLocal else { return }
    takeover.markLocalActivity()
    consume(game.apply(action))
  }

  private func advance(milliseconds: Int) {
    guard takeover.canRunLocal else { return }
    consume(game.advance(milliseconds: milliseconds))
  }

  private func consume(_ events: [TetrisEvent]) {
    if events.contains(where: { $0.kind == .paused }) { companion.paused() }
    let ended = events.contains { $0.kind == .ended }
    let cleared = events.contains { $0.kind == .linesCleared }
    let locked = events.contains { $0.kind == .locked } && game.state.phase != .clearing
    if ended || cleared || locked {
      companion.observe(snapshot(event: ended ? "end" : "clear"), ended: ended, app: app)
    }
  }

  private func reviewRound() {
    preparePanel {
      companion.prepareConversation()
      showingConversation = true
      var request = snapshot(event: "chat")
      request.message = "请根据本局提供的真实数据，陪我简短回顾这一局，不要编造具体摆法。"
      companion.send(request, automatic: false, app: app)
    }
  }

  private func snapshot(event: String) -> TetrisCompanionRequest {
    let board = game.board
    var height = 0
    var holes = 0
    for column in 0..<TetrisGame.width {
      var occupied = false
      for row in 0..<TetrisGame.height {
        if board[row][column] != nil {
          occupied = true
          height = max(height, TetrisGame.height - row)
        } else if occupied {
          holes += 1
        }
      }
    }
    return TetrisCompanionRequest(
      event: event, score: game.score, lines: game.lines, height: height, holes: holes)
  }
}

private struct TetrisBoard: View {
  let game: TetrisGame
  let countdown: Int?
  var ended = false

  var body: some View {
    GeometryReader { proxy in
      let cellSide = max(
        1,
        min(
          (proxy.size.width - 12 - 18) / CGFloat(TetrisGame.width),
          (proxy.size.height - 12 - 38) / CGFloat(TetrisGame.height)))
      let activeCells = Set(game.activeCells.map { $0.row * TetrisGame.width + $0.column })
      let board = game.board
      let ghostCells = Set(game.ghostCells.map { $0.row * TetrisGame.width + $0.column })
      LazyVGrid(
        columns: Array(repeating: GridItem(.fixed(cellSide), spacing: 2), count: TetrisGame.width),
        spacing: 2
      ) {
        ForEach(0..<(TetrisGame.width * TetrisGame.height), id: \.self) { index in
          let row = index / TetrisGame.width
          let column = index % TetrisGame.width
          let kind = activeCells.contains(index) ? game.activeKind : board[row][column]
          let isGhost = kind == nil && ghostCells.contains(index)
          RoundedRectangle(cornerRadius: max(2, cellSide * 0.12))
            .fill(
              kind.map(TetrisGame.color(for:))
                ?? (isGhost ? Color.brand.opacity(0.1) : Color.sectionFill)
            )
            .overlay {
              RoundedRectangle(cornerRadius: max(2, cellSide * 0.12))
                .stroke(
                  isGhost
                    ? Color.brand.opacity(0.6)
                    : Color.appBackground.opacity(kind == nil ? 0.2 : 0.65), lineWidth: 1)
            }
            .frame(width: cellSide, height: cellSide)
        }
      }
      .padding(6)
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
      .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
      .overlay(alignment: .center) {
        if game.isPaused || game.isGameOver || ended || game.state.phase == .ready {
          Color.appBackground.opacity(0.72)
            .overlay {
              Text(
                countdown.map(String.init)
                  ?? (game.isGameOver || ended ? "本局结束" : (game.state.phase == .ready ? "准备好后，点开始" : "暂停中"))
              )
              .font(.headline.bold())
              .foregroundStyle(Color.brand)
              .padding(.horizontal, 14)
              .padding(.vertical, 9)
              .background(Color.sectionFill, in: Capsule())
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
      }
    }
    .accessibilityLabel("俄罗斯方块棋盘，已消除 \(game.lines) 行")
  }
}

private struct TetrisNextPiece: View {
  let kind: TetrisKind
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

  var body: some View {
    LazyVGrid(columns: columns, spacing: 2) {
      ForEach(0..<16, id: \.self) { index in
        let coordinates = kind.cells(rotation: 0)
        let occupied = coordinates.contains { $0.column == index % 4 && $0.row == index / 4 }
        RoundedRectangle(cornerRadius: 3)
          .fill(occupied ? TetrisGame.color(for: kind) : Color.sectionFill.opacity(0.65))
          .aspectRatio(1, contentMode: .fit)
      }
    }
    .padding(6)
    .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 10))
    .accessibilityLabel("下一个方块")
  }
}

extension TetrisGame {
  fileprivate static func color(for kind: TetrisKind) -> Color {
    switch kind {
    case .cyan: .cyan
    case .blue: .blue
    case .orange: .orange
    case .yellow: .yellow
    case .green: .green
    case .purple: .purple
    case .red: .red
    }
  }
}
