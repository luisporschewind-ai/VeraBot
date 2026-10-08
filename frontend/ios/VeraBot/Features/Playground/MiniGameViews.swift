import SwiftUI

struct SokobanGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var levelIndex = 0
    @State private var player = SokobanLevel.levels[0].player
    @State private var boxes = SokobanLevel.levels[0].boxes
    @State private var moves = 0
    @State private var history: [SokobanSnapshot] = []
    @State private var showingLevelComplete = false
    @State private var showingAllDone = false

    private var level: SokobanLevel { SokobanLevel.levels[levelIndex] }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("第 \(levelIndex + 1) 关 · 慢慢规划路线")
                            .font(.headline)
                        Text("把所有箱子推到圆点上。箱子只能推，不能拉。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("\(moves) 步", systemImage: "figure.walk")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brand)
                }

                SokobanBoard(level: level, player: player, boxes: boxes, onMove: move)
                    .aspectRatio(CGFloat(level.width) / CGFloat(level.height), contentMode: .fit)
                    .gesture(DragGesture(minimumDistance: 18).onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dx) > abs(dy) { move(dx > 0 ? .right : .left) }
                        else { move(dy > 0 ? .down : .up) }
                    })

                HStack(spacing: 12) {
                    Button { undo() } label: {
                        Label("撤销", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .disabled(history.isEmpty)

                    Button { restart() } label: {
                        Label("重开", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .prominentButtonStyle()
                }

                VStack(spacing: 7) {
                    SokobanDirectionButton(symbol: "chevron.up", label: "向上") { move(.up) }
                    HStack(spacing: 7) {
                        SokobanDirectionButton(symbol: "chevron.left", label: "向左") { move(.left) }
                        SokobanDirectionButton(symbol: "chevron.down", label: "向下") { move(.down) }
                        SokobanDirectionButton(symbol: "chevron.right", label: "向右") { move(.right) }
                    }
                }
                .padding(.top, 2)

                Text("可以滑动棋盘，也可以用方向键。推错了就撤销一步。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle("推箱子")
        .navigationBarTitleDisplayMode(.inline)
        .alert("这一关完成了！", isPresented: $showingLevelComplete) {
            Button(levelIndex + 1 < SokobanLevel.levels.count ? "下一关" : "完成", role: .cancel) {
                advanceLevel()
            }
        } message: {
            Text("用了 \(moves) 步，把箱子都送到了目标点。")
        }
        .alert("全部通关", isPresented: $showingAllDone) {
            Button("再玩一次") { levelIndex = 0; restart() }
            Button("回到游乐场", role: .cancel) { dismiss() }
        } message: {
            Text("两条路线都走通了，做得真好。")
        }
    }

    private func move(_ direction: SokobanDirection) {
        let row = player / level.width
        let column = player % level.width
        let nextRow = row + direction.rowDelta
        let nextColumn = column + direction.columnDelta
        guard (0..<level.height).contains(nextRow), (0..<level.width).contains(nextColumn) else { return }
        let next = nextRow * level.width + nextColumn
        guard !level.walls.contains(next) else { return }
        var nextBoxes = boxes
        if boxes.contains(next) {
            let boxRow = nextRow + direction.rowDelta
            let boxColumn = nextColumn + direction.columnDelta
            guard (0..<level.height).contains(boxRow), (0..<level.width).contains(boxColumn) else { return }
            let destination = boxRow * level.width + boxColumn
            guard !level.walls.contains(destination), !boxes.contains(destination) else { return }
            nextBoxes.remove(next)
            nextBoxes.insert(destination)
        }
        history.append(SokobanSnapshot(player: player, boxes: boxes, moves: moves))
        player = next
        boxes = nextBoxes
        moves += 1
        if boxes == level.goals { showingLevelComplete = true }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        player = previous.player
        boxes = previous.boxes
        moves = previous.moves
    }

    private func restart() {
        player = level.player
        boxes = level.boxes
        moves = 0
        history = []
        showingLevelComplete = false
    }

    private func advanceLevel() {
        showingLevelComplete = false
        guard levelIndex + 1 < SokobanLevel.levels.count else {
            showingAllDone = true
            return
        }
        levelIndex += 1
        restart()
    }
}

private struct SokobanBoard: View {
    let level: SokobanLevel
    let player: Int
    let boxes: Set<Int>
    let onMove: (SokobanDirection) -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width / CGFloat(level.width), proxy.size.height / CGFloat(level.height))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 2), count: level.width), spacing: 2) {
                ForEach(0..<(level.width * level.height), id: \.self) { cell in
                    ZStack {
                        RoundedRectangle(cornerRadius: max(3, side * 0.12))
                            .fill(level.walls.contains(cell) ? Color.brandFill.opacity(0.86) : Color.sectionFill)
                        if level.goals.contains(cell) {
                            Image(systemName: "target")
                                .font(.system(size: side * 0.58, weight: .medium))
                                .foregroundStyle(Color.brand.opacity(0.65))
                        }
                        if boxes.contains(cell) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: side * 0.58))
                                .foregroundStyle(level.goals.contains(cell) ? Color.brandAccent : Color.orange)
                        } else if player == cell {
                            Image(systemName: "person.fill")
                                .font(.system(size: side * 0.58))
                                .foregroundStyle(Color.brand)
                        }
                    }
                    .frame(width: side, height: side)
                    .accessibilityLabel(accessibilityLabel(cell))
                }
            }
            .frame(width: CGFloat(level.width) * side, height: CGFloat(level.height) * side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private func accessibilityLabel(_ cell: Int) -> String {
        if player == cell { return "你的位置" }
        if boxes.contains(cell) { return level.goals.contains(cell) ? "目标上的箱子" : "箱子" }
        if level.goals.contains(cell) { return "目标点" }
        return level.walls.contains(cell) ? "墙" : "地面"
    }
}

private struct SokobanDirectionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .frame(width: 58, height: 46)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private enum SokobanDirection: Equatable {
    case up, down, left, right
    var rowDelta: Int { self == .up ? -1 : (self == .down ? 1 : 0) }
    var columnDelta: Int { self == .left ? -1 : (self == .right ? 1 : 0) }
}

private struct SokobanSnapshot {
    let player: Int
    let boxes: Set<Int>
    let moves: Int
}

private struct SokobanLevel {
    let width: Int
    let height: Int
    let walls: Set<Int>
    let goals: Set<Int>
    let player: Int
    let boxes: Set<Int>

    static let levels = [
        parse(["#######", "#_____#", "#_____#", "#_@$_.#", "#_____#", "#_____#", "#######"]),
        parse(["########", "#___.__#", "#___$__#", "#@__$._#", "#___$__#", "#___.__#", "#______#", "########"])
    ]

    private static func parse(_ rows: [String]) -> SokobanLevel {
        let width = rows.map(\.count).max() ?? 0
        var walls = Set<Int>(), goals = Set<Int>(), boxes = Set<Int>(), player = 0
        for (row, line) in rows.enumerated() {
            for (column, tile) in line.enumerated() {
                let index = row * width + column
                switch tile {
                case "#": walls.insert(index)
                case ".": goals.insert(index)
                case "$": boxes.insert(index)
                case "@": player = index
                case "*": boxes.insert(index); goals.insert(index)
                case "+": player = index; goals.insert(index)
                default: break
                }
            }
        }
        return SokobanLevel(width: width, height: rows.count, walls: walls, goals: goals, player: player, boxes: boxes)
    }
}

struct TwentyQuestionsGameView: View {
    @State private var secret = TwentySecret.all.randomElement()!
    @State private var asked = Set<Int>()
    @State private var turns = 0
    @State private var log: [TwentyAnswer] = []
    @State private var guess = ""
    @State private var result: TwentyResult?

    private var finished: Bool { result != nil }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("我想好了一个东西。选问题来猜，猜测也会占一次机会。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Label("\(turns) / 20 次", systemImage: "bubble.left.and.bubble.right")
                            Spacer()
                            Text("还剩 \(20 - turns) 次")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brand)
                    }

                    if let result {
                        VStack(alignment: .leading, spacing: 7) {
                            Label(result.won ? "猜中了！" : "这次没猜中", systemImage: result.won ? "sparkles" : "heart")
                                .font(.headline)
                                .foregroundStyle(Color.brand)
                            Text(result.won ? "你猜对了：\(secret.name)。要不要再来一局？" : "我想的是「\(secret.name)」。再来一局，换个答案试试？")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("再玩一局") { restart() }
                                .prominentButtonStyle()
                                .padding(.top, 5)
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 17))
                    }

                    if !log.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("刚才的线索").font(.headline)
                            ForEach(log) { item in
                                HStack(spacing: 9) {
                                    Image(systemName: item.yes ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(item.yes ? Color.brandAccent : Color.secondary)
                                    Text(item.prompt)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(item.yes ? "是" : "不是")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 11))
                            }
                        }
                        .id("clues")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("选一个问题问我").font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                            ForEach(Array(TwentyPrompt.all.enumerated()), id: \.offset) { index, prompt in
                                Button {
                                    ask(index, proxy: proxy)
                                } label: {
                                    Text(prompt)
                                        .font(.caption.weight(.medium))
                                        .frame(maxWidth: .infinity, minHeight: 54)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 6)
                                        .background(asked.contains(index) ? Color.appBackground : Color.sectionFill,
                                                    in: RoundedRectangle(cornerRadius: 13))
                                        .foregroundStyle(asked.contains(index) ? Color.secondary : Color.primary)
                                }
                                .buttonStyle(.plain)
                                .disabled(finished || asked.contains(index) || turns >= 20)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text("想直接猜也可以").font(.headline)
                        HStack(spacing: 9) {
                            TextField("输入你的答案", text: $guess)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.done)
                                .onSubmit { submitGuess(proxy: proxy) }
                                .disabled(finished || turns >= 20)
                            Button("猜一猜") { submitGuess(proxy: proxy) }
                                .prominentButtonStyle()
                                .disabled(finished || turns >= 20 || guess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("答案可能是日常物品、动物或食物。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(18)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .themedPageBackground()
            .onChange(of: log.count) { _, _ in
                withAnimation { proxy.scrollTo("clues", anchor: .top) }
            }
        }
        .navigationTitle("二十问")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask(_ index: Int, proxy: ScrollViewProxy) {
        guard !finished, !asked.contains(index), turns < 20 else { return }
        asked.insert(index)
        turns += 1
        log.append(TwentyAnswer(prompt: TwentyPrompt.all[index], yes: secret.features.contains(index)))
        if turns == 20 { result = TwentyResult(won: false) }
    }

    private func submitGuess(proxy: ScrollViewProxy) {
        let candidate = guess.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finished, turns < 20, !candidate.isEmpty else { return }
        turns += 1
        let won = secret.answers.contains(candidate.lowercased()) || candidate == secret.name
        log.append(TwentyAnswer(prompt: "我猜是「\(candidate)」", yes: won))
        guess = ""
        if won { result = TwentyResult(won: true) }
        else if turns == 20 { result = TwentyResult(won: false) }
    }

    private func restart() {
        secret = TwentySecret.all.filter { $0.name != secret.name }.randomElement() ?? TwentySecret.all.randomElement()!
        asked = []
        turns = 0
        log = []
        guess = ""
        result = nil
    }
}

private struct TwentyAnswer: Identifiable {
    let id = UUID()
    let prompt: String
    let yes: Bool
}

private struct TwentyResult {
    let won: Bool
}

private struct TwentySecret {
    let name: String
    let answers: Set<String>
    let features: Set<Int>

    static let all: [TwentySecret] = [
        .init(name: "猫", answers: ["猫", "小猫"], features: [0, 1, 2, 3, 7, 9, 10, 11, 12, 15, 17]),
        .init(name: "狗", answers: ["狗", "小狗"], features: [0, 1, 2, 3, 7, 9, 10, 11, 12, 15, 17]),
        .init(name: "熊猫", answers: ["熊猫", "大熊猫"], features: [0, 1, 2, 3, 7, 9, 10, 11, 15, 17]),
        .init(name: "兔子", answers: ["兔子", "兔"], features: [0, 1, 2, 3, 7, 9, 10, 11, 15, 17]),
        .init(name: "鱼", answers: ["鱼", "小鱼"], features: [0, 1, 2, 3, 6, 9, 10, 11, 15, 17]),
        .init(name: "苹果", answers: ["苹果"], features: [0, 1, 2, 4, 5, 7, 9, 10, 11, 16, 17]),
        .init(name: "香蕉", answers: ["香蕉"], features: [0, 1, 2, 4, 5, 7, 9, 10, 11, 16, 17]),
        .init(name: "西瓜", answers: ["西瓜"], features: [0, 1, 2, 4, 5, 7, 9, 10, 11, 16, 17]),
        .init(name: "冰淇淋", answers: ["冰淇淋", "雪糕"], features: [0, 1, 2, 4, 5, 7, 9, 10, 11, 16, 17]),
        .init(name: "面包", answers: ["面包", "吐司"], features: [0, 1, 2, 4, 5, 7, 9, 10, 11, 16]),
        .init(name: "雨伞", answers: ["雨伞", "伞"], features: [0, 1, 4, 5, 7, 9, 10, 11, 16]),
        .init(name: "书", answers: ["书", "书本"], features: [0, 1, 4, 5, 7, 9, 10, 11, 16]),
        .init(name: "手机", answers: ["手机"], features: [0, 1, 4, 5, 7, 9, 10, 11, 16]),
        .init(name: "自行车", answers: ["自行车", "单车"], features: [0, 1, 4, 5, 8, 9, 10, 11, 16]),
        .init(name: "汽车", answers: ["汽车", "车"], features: [0, 1, 4, 5, 8, 9, 10, 11, 16]),
        .init(name: "飞机", answers: ["飞机"], features: [0, 1, 4, 5, 8, 9, 10, 11, 16]),
        .init(name: "月亮", answers: ["月亮", "月球"], features: [0, 1, 4, 7, 9, 10, 13, 14, 18]),
        .init(name: "太阳", answers: ["太阳"], features: [0, 1, 4, 7, 9, 10, 13, 14, 18]),
        .init(name: "足球", answers: ["足球"], features: [0, 1, 4, 5, 7, 9, 10, 11, 16]),
        .init(name: "机器人", answers: ["机器人"], features: [0, 1, 4, 5, 7, 9, 10, 11, 16, 19])
    ]
}

private enum TwentyPrompt {
    static let all = [
        "它是活的吗？", "现实中能见到吗？", "它有生命吗？", "它是动物吗？", "它是吃的吗？",
        "它是人造的吗？", "它生活在水里吗？", "它可以吃吗？", "它能载人吗？", "家里常见吗？",
        "它能移动吗？", "它可以拿在手里吗？", "它有四条腿吗？", "它在天上吗？", "它会发光吗？",
        "它有毛吗？", "它通常是圆的吗？", "它会长大吗？", "它比房子大吗？", "它有智能吗？"
    ]
}

struct TetrisGameView: View {
    @State private var game = TetrisGame()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 10)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.isGameOver ? "这一局结束啦" : "方块落下，慢慢找位置")
                            .font(.headline)
                        Text("消除整行得分，速度会逐渐加快。")
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

                HStack(spacing: 12) {
                    TetrisBoard(game: game)
                        .aspectRatio(0.5, contentMode: .fit)
                        .frame(maxWidth: 290)
                    VStack(spacing: 8) {
                        Text("下一个")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TetrisNextPiece(kind: game.nextKind)
                            .frame(width: 74, height: 74)
                        Spacer(minLength: 8)
                        Button {
                            game.isPaused.toggle()
                        } label: {
                            Image(systemName: game.isPaused ? "play.fill" : "pause.fill")
                                .font(.headline)
                                .frame(width: 48, height: 44)
                                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(game.isGameOver)
                        .accessibilityLabel(game.isPaused ? "继续" : "暂停")

                        Button {
                            game = TetrisGame()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                                .frame(width: 48, height: 44)
                                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("重新开始")
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity)

                if game.isGameOver || game.isPaused {
                    Text(game.isGameOver ? "再来一局，试试新的摆法。" : "游戏已暂停，准备好后继续。")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 10) {
                    TetrisControlButton(symbol: "chevron.left", label: "向左") { game.move(-1) }
                    TetrisControlButton(symbol: "chevron.down", label: "加速下落") { game.softDrop() }
                    TetrisControlButton(symbol: "rotate.right", label: "旋转") { game.rotate() }
                    TetrisControlButton(symbol: "chevron.right", label: "向右") { game.move(1) }
                    TetrisControlButton(symbol: "arrow.down.to.line", label: "直接落下") { game.hardDrop() }
                }
                .disabled(game.isPaused || game.isGameOver)

                Text("左右移动 · 旋转 · 加速下落 · 直接落下")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(18)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle("俄罗斯方块")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: game.isPaused || game.isGameOver ? -1 : game.dropInterval) {
            guard !game.isPaused, !game.isGameOver else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(game.dropInterval))
                guard !Task.isCancelled else { return }
                game.dropOne()
            }
        }
    }
}

private struct TetrisBoard: View {
    let game: TetrisGame
    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 2), count: TetrisGame.width)

    var body: some View {
        GeometryReader { proxy in
            let cellSide = proxy.size.width / CGFloat(TetrisGame.width)
            let activeCells = Set(game.activeCells.map { $0.row * TetrisGame.width + $0.column })
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<(TetrisGame.width * TetrisGame.height), id: \.self) { index in
                    let row = index / TetrisGame.width
                    let column = index % TetrisGame.width
                    let kind = activeCells.contains(index) ? game.activeKind : game.board[row][column]
                    RoundedRectangle(cornerRadius: max(2, cellSide * 0.12))
                        .fill(kind.map(TetrisGame.color(for:)) ?? Color.sectionFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: max(2, cellSide * 0.12))
                                .stroke(Color.appBackground.opacity(kind == nil ? 0.2 : 0.65), lineWidth: 1)
                        }
                        .frame(width: cellSide, height: cellSide)
                }
            }
            .frame(width: proxy.size.width, height: cellSide * CGFloat(TetrisGame.height), alignment: .top)
            .padding(6)
            .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .center) {
                if game.isPaused || game.isGameOver {
                    Color.appBackground.opacity(0.72)
                        .overlay {
                            Text(game.isGameOver ? "本局结束" : "暂停中")
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

private struct TetrisControlButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private enum TetrisKind: Int, CaseIterable {
    case cyan, blue, orange, yellow, green, purple, red

    func cells(rotation: Int) -> [TetrisCell] {
        let base: [TetrisCell]
        switch self {
        case .cyan: base = [cell(0, 1), cell(1, 1), cell(2, 1), cell(3, 1)]
        case .blue: base = [cell(0, 0), cell(0, 1), cell(1, 1), cell(2, 1)]
        case .orange: base = [cell(2, 0), cell(0, 1), cell(1, 1), cell(2, 1)]
        case .yellow: base = [cell(1, 0), cell(2, 0), cell(1, 1), cell(2, 1)]
        case .green: base = [cell(1, 0), cell(2, 0), cell(0, 1), cell(1, 1)]
        case .purple: base = [cell(1, 0), cell(0, 1), cell(1, 1), cell(2, 1)]
        case .red: base = [cell(0, 0), cell(1, 0), cell(1, 1), cell(2, 1)]
        }
        return (0..<rotation).reduce(base) { cells, _ in
            cells.map { TetrisCell(column: 3 - $0.row, row: $0.column) }
        }
    }

    private func cell(_ column: Int, _ row: Int) -> TetrisCell {
        TetrisCell(column: column, row: row)
    }
}

private struct TetrisCell: Hashable {
    let column: Int
    let row: Int
}

private struct TetrisGame {
    static let width = 10
    static let height = 20

    private(set) var board = Array(repeating: Array<TetrisKind?>(repeating: nil, count: width), count: height)
    private(set) var activeKind: TetrisKind
    private(set) var nextKind: TetrisKind
    private(set) var activeX = 3
    private(set) var activeY = 0
    private(set) var rotation = 0
    private(set) var score = 0
    private(set) var lines = 0
    var isPaused = false
    private(set) var isGameOver = false

    var dropInterval: Int { max(130, 620 - (lines / 10) * 55) }
    var activeCells: [TetrisCell] {
        activeKind.cells(rotation: rotation).map { TetrisCell(column: activeX + $0.column, row: activeY + $0.row) }
    }

    init() {
        activeKind = TetrisKind.allCases.randomElement() ?? .cyan
        nextKind = TetrisKind.allCases.randomElement() ?? .yellow
    }

    mutating func move(_ direction: Int) {
        guard canPlay, fits(kind: activeKind, rotation: rotation, x: activeX + direction, y: activeY) else { return }
        activeX += direction
    }

    mutating func rotate() {
        guard canPlay else { return }
        let candidate = (rotation + 1) % 4
        for offset in [0, -1, 1, -2, 2] {
            if fits(kind: activeKind, rotation: candidate, x: activeX + offset, y: activeY) {
                rotation = candidate
                activeX += offset
                return
            }
        }
    }

    mutating func softDrop() {
        guard canPlay else { return }
        if fits(kind: activeKind, rotation: rotation, x: activeX, y: activeY + 1) {
            activeY += 1
            score += 1
        } else {
            lockPiece()
        }
    }

    mutating func hardDrop() {
        guard canPlay else { return }
        var distance = 0
        while fits(kind: activeKind, rotation: rotation, x: activeX, y: activeY + 1) {
            activeY += 1
            distance += 1
        }
        score += distance * 2
        lockPiece()
    }

    mutating func dropOne() {
        guard canPlay else { return }
        if fits(kind: activeKind, rotation: rotation, x: activeX, y: activeY + 1) {
            activeY += 1
        } else {
            lockPiece()
        }
    }

    static func color(for kind: TetrisKind) -> Color {
        switch kind {
        case .cyan: Color.cyan
        case .blue: Color.blue
        case .orange: Color.orange
        case .yellow: Color.yellow
        case .green: Color.green
        case .purple: Color.purple
        case .red: Color.red
        }
    }

    private var canPlay: Bool { !isPaused && !isGameOver }

    private func fits(kind: TetrisKind, rotation: Int, x: Int, y: Int) -> Bool {
        for cell in kind.cells(rotation: rotation) {
            let column = x + cell.column
            let row = y + cell.row
            if column < 0 || column >= Self.width || row >= Self.height { return false }
            if row >= 0 && board[row][column] != nil { return false }
        }
        return true
    }

    private mutating func lockPiece() {
        for cell in activeCells {
            guard cell.row >= 0 else { isGameOver = true; return }
            board[cell.row][cell.column] = activeKind
        }
        clearFullRows()
        activeKind = nextKind
        nextKind = TetrisKind.allCases.randomElement() ?? .cyan
        activeX = 3
        activeY = 0
        rotation = 0
        if !fits(kind: activeKind, rotation: rotation, x: activeX, y: activeY) { isGameOver = true }
    }

    private mutating func clearFullRows() {
        let remaining = board.filter { $0.contains(where: { $0 == nil }) }
        let cleared = Self.height - remaining.count
        guard cleared > 0 else { return }
        board = Array(repeating: Array<TetrisKind?>(repeating: nil, count: Self.width), count: cleared) + remaining
        lines += cleared
        score += [0, 100, 300, 500, 800][min(cleared, 4)]
    }
}
