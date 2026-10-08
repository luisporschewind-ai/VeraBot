import SwiftUI
import VeraBotCore

struct PlaygroundView: View {
    @State private var showingSudoku = false
    @State private var showingSokoban = false
    @State private var showingTwentyQuestions = false
    @State private var showingTetris = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("游乐场")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.brandText)
                        Text("和 Bot 一起玩点轻松的。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button { showingSudoku = true } label: {
                        SudokuFeatureCard()
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 12) {
                        WorldSectionTitle(title: "挑一个玩法", subtitle: "短短几分钟，也可以一起开心一下")
                        VStack(spacing: 10) {
                            ForEach(PlaygroundGame.allCases.filter { $0 != .sudoku }) { game in
                                Button { open(game) } label: {
                                    GameIdeaRow(game: game)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "heart.text.clipboard")
                            .font(.title3)
                            .foregroundStyle(Color.brand)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("卡住时，我们一起想")
                                .font(.subheadline.weight(.semibold))
                            Text("先轻松玩一局，Bot 的互动方式还在继续设计。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .themedPageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingSudoku) {
                SudokuGameView()
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $showingSokoban) {
                SokobanGameView().toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $showingTwentyQuestions) {
                TwentyQuestionsGameView().toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(isPresented: $showingTetris) {
                TetrisGameView().toolbar(.hidden, for: .tabBar)
            }
        }
    }

    private func open(_ game: PlaygroundGame) {
        switch game {
        case .sokoban: showingSokoban = true
        case .twentyQuestions: showingTwentyQuestions = true
        case .tetris: showingTetris = true
        case .sudoku: showingSudoku = true
        }
    }
}

private struct SudokuFeatureCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("数字游戏", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.20), in: Capsule())
                Spacer()
                Text("可以开局")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("数独")
                        .font(.title.bold())
                    Text("一起找线索，享受解开谜题的瞬间。")
                        .font(.subheadline)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.white.opacity(0.88))
                }
                Spacer(minLength: 0)
                SudokuGlyph()
                    .frame(width: 78, height: 78)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                Text("来一盘数独")
                    .font(.footnote.weight(.semibold))
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.17), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [Color.brandFill, Color.brandAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SudokuGameView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries = SudokuPuzzle.start
    @State private var selectedCell: Int?
    @State private var checkedConflicts: Set<Int> = []
    @State private var moves: [SudokuMove] = []
    @State private var notice: String?
    @State private var showingCompletion = false

    private var filledCount: Int { entries.filter { $0 != 0 }.count }
    private var selectedIsGiven: Bool { selectedCell.map(SudokuPuzzle.givens.contains) ?? true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("入门 · 经典数独")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brand)
                    Text("选一个空格，再填入数字。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SudokuBoard(
                    entries: entries,
                    selectedCell: selectedCell,
                    conflicts: checkedConflicts,
                    onSelect: select
                )
                .aspectRatio(1, contentMode: .fit)

                HStack {
                    Label("已填 \(filledCount) / 81", systemImage: "square.grid.3x3")
                    Spacer()
                    if !moves.isEmpty {
                        Button("撤销") { undo() }
                            .font(.subheadline.weight(.medium))
                            .accessibilityHint("撤销上一次填入或擦除")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let notice {
                    Label(notice, systemImage: checkedConflicts.isEmpty ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(checkedConflicts.isEmpty ? Color.brandAccent : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12))
                }

                SudokuNumberPad(isEnabled: selectedCell != nil && !selectedIsGiven, onNumber: enter)

                HStack(spacing: 12) {
                    Button { eraseSelected() } label: {
                        Label("擦除", systemImage: "delete.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedCell == nil || selectedIsGiven)

                    Button("检查冲突") { checkBoard() }
                        .frame(maxWidth: .infinity)
                        .prominentButtonStyle()
                }

                Text("检查只会标出冲突，不会扣分或替你改数字。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle("数独")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("重开") { restart() }
                    .font(.subheadline)
            }
        }
        .alert("完成这一局", isPresented: $showingCompletion) {
            Button("回到游乐场") { dismiss() }
            Button("再玩一次", role: .cancel) { restart() }
        } message: {
            Text("你一步一步解开了这道数独。")
        }
    }

    private func select(_ index: Int) {
        selectedCell = index
    }

    private func enter(_ number: Int) {
        guard let index = selectedCell, !SudokuPuzzle.givens.contains(index) else { return }
        setEntry(number, at: index)
    }

    private func eraseSelected() {
        guard let index = selectedCell, !SudokuPuzzle.givens.contains(index) else { return }
        setEntry(0, at: index)
    }

    private func setEntry(_ number: Int, at index: Int) {
        moves.append(SudokuMove(index: index, previous: entries[index]))
        entries[index] = number
        checkedConflicts = []
        notice = nil
        if entries == SudokuPuzzle.solution {
            showingCompletion = true
        }
    }

    private func undo() {
        guard let move = moves.popLast() else { return }
        entries[move.index] = move.previous
        checkedConflicts = []
        notice = nil
    }

    private func checkBoard() {
        checkedConflicts = SudokuPuzzle.conflicts(in: entries)
        if entries == SudokuPuzzle.solution {
            showingCompletion = true
        } else if checkedConflicts.isEmpty {
            notice = "目前没有发现规则冲突，可以继续。"
        } else {
            notice = "发现数字冲突，已在棋盘上标出。"
        }
    }

    private func restart() {
        entries = SudokuPuzzle.start
        selectedCell = nil
        checkedConflicts = []
        moves = []
        notice = nil
    }
}

private struct SudokuBoard: View {
    let entries: [Int]
    let selectedCell: Int?
    let conflicts: Set<Int>
    let onSelect: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 9)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(0..<81, id: \.self) { index in
                    Button { onSelect(index) } label: {
                        Text(entries[index] == 0 ? " " : "\(entries[index])")
                            .font(.system(size: max(14, side / 21), weight: SudokuPuzzle.givens.contains(index) ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(cellForeground(index))
                            .frame(width: side / 9, height: side / 9)
                            .background(cellBackground(index))
                            .overlay {
                                Rectangle().stroke(Color.primary.opacity(0.16), lineWidth: 0.45)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: index))
                    .accessibilityAddTraits(selectedCell == index ? .isSelected : [])
                }
            }
            .frame(width: side, height: side)
            .overlay {
                SudokuGridLines()
                    .stroke(Color.primary.opacity(0.54), lineWidth: 1.5)
                    .padding(0.5)
            }
            .overlay {
                Rectangle().stroke(Color.primary.opacity(0.62), lineWidth: 1.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    private func cellBackground(_ index: Int) -> Color {
        if conflicts.contains(index) { return Color.orange.opacity(0.20) }
        if selectedCell == index { return Color.brand.opacity(0.22) }
        if let selectedCell,
           index / 9 == selectedCell / 9 || index % 9 == selectedCell % 9 {
            return Color.brandSoft.opacity(0.7)
        }
        return SudokuPuzzle.givens.contains(index) ? Color.sectionFill : Color.appBackground
    }

    private func cellForeground(_ index: Int) -> Color {
        conflicts.contains(index) ? Color.orange : (SudokuPuzzle.givens.contains(index) ? Color.primary : Color.brand)
    }

    private func accessibilityLabel(for index: Int) -> String {
        let row = index / 9 + 1
        let column = index % 9 + 1
        let number = entries[index] == 0 ? "空格" : "\(entries[index])"
        return "第\(row)行第\(column)列，\(number)\(SudokuPuzzle.givens.contains(index) ? "，题目数字" : "")"
    }
}

private struct SudokuGridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 1...2 {
            let position = rect.width * CGFloat(step) / 3
            path.move(to: CGPoint(x: position, y: 0))
            path.addLine(to: CGPoint(x: position, y: rect.height))
            path.move(to: CGPoint(x: 0, y: rect.height * CGFloat(step) / 3))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * CGFloat(step) / 3))
        }
        return path
    }
}

private struct SudokuNumberPad: View {
    let isEnabled: Bool
    let onNumber: (Int) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...9, id: \.self) { number in
                Button { onNumber(number) } label: {
                    Text("\(number)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.48)
                .accessibilityLabel("填写数字 \(number)")
            }
        }
    }
}

private struct SudokuMove {
    let index: Int
    let previous: Int
}

private enum SudokuPuzzle {
    static let start = Array("530070000600195000098000060800060003400803001700020006060000280000419005000080079").compactMap(\.wholeNumberValue)
    static let solution = Array("534678912672195348198342567859761423426853791713924856961537284287419635345286179").compactMap(\.wholeNumberValue)
    static let givens: Set<Int> = Set(start.indices.filter { start[$0] != 0 })

    static func conflicts(in entries: [Int]) -> Set<Int> {
        var result = Set<Int>()
        for row in 0..<9 {
            result.formUnion(duplicates(in: (0..<9).map { row * 9 + $0 }, entries: entries))
        }
        for column in 0..<9 {
            result.formUnion(duplicates(in: (0..<9).map { $0 * 9 + column }, entries: entries))
        }
        for boxRow in 0..<3 {
            for boxColumn in 0..<3 {
                let indexes = (0..<3).flatMap { row in
                    (0..<3).map { column in (boxRow * 3 + row) * 9 + boxColumn * 3 + column }
                }
                result.formUnion(duplicates(in: indexes, entries: entries))
            }
        }
        return result
    }

    private static func duplicates(in indexes: [Int], entries: [Int]) -> Set<Int> {
        let groups = Dictionary(grouping: indexes.filter { entries[$0] != 0 }, by: { entries[$0] })
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0 })
    }
}

private struct SudokuGlyph: View {
    private let digits = ["1", "", "4", "", "5", "", "7", "", "2"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.20))
                    .overlay {
                        Text(digit)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
            }
        }
        .padding(5)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
    }
}

private enum PlaygroundGame: String, CaseIterable, Identifiable {
    case sudoku
    case sokoban
    case twentyQuestions
    case tetris

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sudoku: "数独"
        case .sokoban: "推箱子"
        case .twentyQuestions: "二十问"
        case .tetris: "俄罗斯方块"
        }
    }

    var symbol: String {
        switch self {
        case .sudoku: "square.grid.3x3"
        case .sokoban: "shippingbox"
        case .twentyQuestions: "bubble.left.and.text.bubble.right"
        case .tetris: "square.grid.4x3.fill"
        }
    }

    var description: String {
        switch self {
        case .sudoku: "一格一格找出规律，Bot 可以给你渐进提示。"
        case .sokoban: "一起规划路线，找到把箱子推到目标点的方法。"
        case .twentyQuestions: "Bot 想一个答案，你来提问，看看能不能猜中。"
        case .tetris: "旋转和摆放方块，消行得分，看看能坚持多久。"
        }
    }

    var detail: String {
        switch self {
        case .sudoku: "你决定何时需要提示。Bot 可以解释某个数字为什么适合这一格，留出自己推理的空间。"
        case .sokoban: "每一步都会改变路线。Bot 可以和你一起看当前局面，讨论下一步会带来什么结果。"
        case .twentyQuestions: "Bot 负责主持和回答问题，也可以在你想换位置时与你交换角色。"
        case .tetris: "先享受方块下落和消行的节奏，后续再探索 Bot 可以怎样陪玩。"
        }
    }
}

private struct GameIdeaRow: View {
    let game: PlaygroundGame

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: game.symbol)
                .font(.title3)
                .foregroundStyle(Color.brand)
                .frame(width: 46, height: 46)
                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(game.title).font(.headline)
                    Text("可以开局")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.appBackground, in: Capsule())
                }
                Text(game.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct IslandView: View {
    @Environment(AppState.self) private var app
    @State private var bots: [Bot] = []
    @State private var errorText: String?
    @State private var loading = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("我的小岛")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.brandText)
                        Text("一片属于你和 Bot 伙伴的小天地。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ContinueTogetherCard()

                    VStack(alignment: .leading, spacing: 12) {
                        WorldSectionTitle(title: "你的 Bot 团队", subtitle: "找一位伙伴，聊聊接下来想做的事")
                        if loading && bots.isEmpty {
                            ProgressView("正在找你的伙伴…")
                                .frame(maxWidth: .infinity, minHeight: 100)
                        } else if let errorText {
                            ContentUnavailableView {
                                Label("暂时没能加载伙伴", systemImage: "wifi.exclamationmark")
                            } description: {
                                Text(errorText)
                            } actions: {
                                Button("再试一次") { Task { await loadBots() } }
                                    .prominentButtonStyle()
                            }
                        } else if bots.isEmpty {
                            ContentUnavailableView("还没有 Bot 伙伴", systemImage: "person.2", description: Text("创建一位 Bot，就可以邀请它一起聊天和做事。"))
                        } else {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(bots) { bot in
                                    NavigationLink {
                                        ChatView(bot: bot, api: app.api)
                                            .toolbar(.hidden, for: .tabBar)
                                    } label: {
                                        IslandBotCard(bot: bot)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        WorldSectionTitle(title: "共同收藏", subtitle: "你们一起经历过的，会在这里留下痕迹")
                        MemoryShelfCard()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .themedPageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadBots() }
            .refreshable { await loadBots() }
        }
    }

    private func loadBots() async {
        loading = true
        defer { loading = false }
        do {
            let response = try await app.api.bots()
            guard app.token != nil else { return }
            bots = BotOrdering.sorted(response.bots)
            for bot in response.bots {
                app.avatars.reconcileBot(id: bot.id, hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt)
            }
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }
}

private struct ContinueTogetherCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("正在继续", systemImage: "arrow.turn.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brand)
                Spacer()
                Image(systemName: "sparkle")
                    .foregroundStyle(Color.brandAccent)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("下一段共同经历，等你来开启")
                    .font(.headline)
                Text("开始一局游戏，或和伙伴聊聊你正在做的事。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Image(systemName: "gamecontroller")
                Text("从游乐场开始")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.brand)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct IslandBotCard: View {
    let bot: Bot
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                          hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(bot.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(bot.persona.isEmpty ? "点这里，和伙伴聊聊" : bot.persona)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 32, alignment: .topLeading)
            }
            HStack(spacing: 5) {
                Image(systemName: "bubble.left")
                Text("去找它")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.brand)
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
        .padding(14)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct MemoryShelfCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.text.square")
                .font(.title2)
                .foregroundStyle(Color.brandAccent)
                .frame(width: 48, height: 48)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text("第一张纪念卡还空着")
                    .font(.subheadline.weight(.semibold))
                Text("一起完成一件事后，把这段经历收进来。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ExploreIdeasView: View {
    private let groups = ExploreIdea.groups

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("想法正在这里慢慢长大")
                            .font(.headline)
                        Text("点开一项，看看它可能带来的体验和后续规划。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.ideas) { idea in
                            NavigationLink {
                                ExploreIdeaDetailView(idea: idea)
                                    .toolbar(.hidden, for: .tabBar)
                            } label: {
                                ExploreIdeaRow(idea: idea)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .themedPageBackground()
            .navigationTitle("探索")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct ExploreIdeaRow: View {
    let idea: ExploreIdea

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: idea.symbol)
                .font(.headline)
                .foregroundStyle(Color.brand)
                .frame(width: 36, height: 36)
                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(idea.title).font(.subheadline.weight(.medium))
                Text(idea.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ExploreIdeaDetailView: View {
    let idea: ExploreIdea

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(idea.category, systemImage: idea.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brand)
                    Text(idea.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.brandText)
                    Text(idea.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                DetailInfoCard(title: "想带来的体验", content: idea.experience, symbol: "sparkles")
                DetailInfoCard(title: "Bot 可以怎么参与", content: idea.botRole, symbol: "person.crop.circle.badge.questionmark")
                VStack(alignment: .leading, spacing: 12) {
                    WorldSectionTitle(title: "可以这样逐步展开", subtitle: "当前是规划占位，细节会随着讨论补充")
                    ForEach(Array(idea.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.brand)
                                .frame(width: 26, height: 26)
                                .background(Color.brandSoft, in: Circle())
                            Text(step)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Text("灵感占位 · 尚未实现")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle(idea.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DetailInfoCard: View {
    let title: String
    let content: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brand)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct WorldSectionTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExploreIdea: Identifiable {
    let id: String
    let category: String
    let title: String
    let summary: String
    let experience: String
    let botRole: String
    let steps: [String]
    let symbol: String

    static let groups: [ExploreIdeaGroup] = [
        ExploreIdeaGroup(title: "工作与生活", ideas: [
            ExploreIdea(id: "work", category: "工作与生活", title: "Bot 团队的 Work 能力", summary: "和 Bot 一起拆解目标，推进手头的工作。", experience: "Vera Bot 团队不只回答问题，也能陪用户看清任务的下一步，并一起产出实际可用的结果。", botRole: "合适的 Bot 可以梳理目标、发现卡点、帮忙比较方案；遇到顾虑时先倾听再协助推进。", steps: ["选一个真实工作场景", "讨论 Bot 如何发现阻塞并协作", "定义能看见的进展与结果"], symbol: "briefcase"),
            ExploreIdea(id: "initiative", category: "工作与生活", title: "善解人意的主动性", summary: "理解卡点与顾虑，温暖地陪用户成长。", experience: "Bot 留意任务进展与对话中尚未解决的问题，用一个恰当的问题帮助用户厘清思路。", botRole: "先求证自己的理解，给一小步可选建议，也尊重用户暂停或换方向。", steps: ["从用户明确的目标与进度开始", "设计卡点识别和温和追问", "逐步讨论跨会话的主动支持"], symbol: "heart"),
            ExploreIdea(id: "tools", category: "工作与生活", title: "生活与工作小工具", summary: "让现有小工具成为 Bot 团队能一起使用的能力。", experience: "把 Vera、Trans Glass 和其他小工具带来的灵感，转化为适合个人生活与工作的协助。", botRole: "根据任务担任合适的协作伙伴，帮助用户把想法变成步骤或作品。", steps: ["收集重复且有价值的小场景", "挑出一个能独立完成的工具体验", "明确与 Bot 对话的衔接点"], symbol: "wrench.and.screwdriver")
        ]),
        ExploreIdeaGroup(title: "安静与陪伴", ideas: [
            ExploreIdea(id: "reading", category: "安静与陪伴", title: "共同阅读", summary: "读书、独处、思考，也可以随时聊聊。", experience: "用户按自己的节奏阅读，Bot 记住经用户同意的进度，在用户想讨论时成为读书伙伴。", botRole: "解释难点、提出温和的问题、保护阅读节奏并避免剧透。", steps: ["选定阅读方式与进度", "讨论 Bot 的陪读角色", "沉淀笔记或共同阅读手记"], symbol: "book"),
            ExploreIdea(id: "cave", category: "安静与陪伴", title: "树洞", summary: "一个安静说说心事、整理思绪的地方。", experience: "用户可以倾诉、独处或请求帮助，不必把每次对话都变成任务。", botRole: "先听懂用户的感受和疑问，再询问对方希望被倾听还是一起想办法。", steps: ["确定安静陪伴的体验边界", "设计倾听与回应方式", "讨论隐私、记忆和主动关怀"], symbol: "leaf")
        ]),
        ExploreIdeaGroup(title: "探索与旅程", ideas: [
            ExploreIdea(id: "space", category: "探索与旅程", title: "Bot Space 与发现", summary: "发现 Bot、活动、知识或新的主题空间。", experience: "用户可以通过主题空间找到适合当下的一位 Bot 或一件可做的事。", botRole: "担任空间里的伙伴或向导，让用户知道这里能做什么。", steps: ["厘清 Space 与小岛的关系", "确定 Discover／Find 的对象", "挑一个主题空间示例"], symbol: "safari"),
            ExploreIdea(id: "travel", category: "探索与旅程", title: "Bot 旅行与 Journey", summary: "派一位 Bot 出发，等它带回故事和纪念品。", experience: "一次旅程可以成为新的谈资，并在小岛留下明信片、见闻等纪念。", botRole: "根据个性去探索，回来分享旅程中值得记住的片段。", steps: ["确定虚构旅行或现实探索", "设计出发、等待与归来的节奏", "让纪念品能继续引出对话"], symbol: "map")
        ]),
        ExploreIdeaGroup(title: "游戏与互动", ideas: [
            ExploreIdea(id: "games", category: "游戏与互动", title: "数独、推箱子与小游戏", summary: "Bot 可以当队友、对手或温和的提示者。", experience: "规则清楚、随时能开始的小游戏，为用户带来一段轻松互动。", botRole: "按游戏担任角色；当用户卡住时先了解卡点，再提供适度提示。", steps: ["选定首个小游戏", "确定规则由程序负责的部分", "设计 Bot 的陪玩与提示方式"], symbol: "gamecontroller"),
            ExploreIdea(id: "social-play", category: "游戏与互动", title: "漂流瓶与广场", summary: "围绕轻互动、分享和热闹氛围继续探索。", experience: "用户可能遇到新故事、新玩法或来自他人的作品。", botRole: "在安全、清晰的社交边界里做主持人或同行者。", steps: ["确定内容来自用户、Bot 还是系统", "明确公开和互动的边界", "再决定是否需要社区入口"], symbol: "paperplane")
        ]),
        ExploreIdeaGroup(title: "伙伴与世界", ideas: [
            ExploreIdea(id: "personality", category: "伙伴与世界", title: "Bot 人设与节日皮肤", summary: "让团队成员有性格、有形象，也有节日气氛。", experience: "Bot 的说话方式、专长与外观共同表达鲜明个性。", botRole: "以一致的人设参与工作、游戏和生活活动。", steps: ["整理人设和专长的关系", "探索节日外观主题", "让形象变化有用户控制"], symbol: "face.smiling"),
            ExploreIdea(id: "home", category: "伙伴与世界", title: "小楼、小院与共同纪念", summary: "让共同经历在小岛里有可以回望的地方。", experience: "完成过的活动留下纪念卡或勋章，逐渐让小岛呈现自己的故事。", botRole: "成为共同经历的参与者，也可以陪用户回看这些故事。", steps: ["从活动真实产出的纪念开始", "探索小楼小院如何呈现", "保持无积分和无等级压力"], symbol: "house")
        ])
    ]
}

private struct ExploreIdeaGroup: Identifiable {
    let title: String
    let ideas: [ExploreIdea]
    var id: String { title }
}
