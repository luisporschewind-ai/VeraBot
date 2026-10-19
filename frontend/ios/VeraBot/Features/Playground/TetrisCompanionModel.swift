import Foundation
import Observation
import VeraBotCore
import VeraBotNetworking

@MainActor @Observable
final class TetrisCompanionModel {
    var bots: [Bot] = []
    var selected: Bot?
    var loading = false
    var loadError: String?
    var error: String?
    var text = ""
    var turns: [TetrisCompanionTurn] = []
    var requesting = false
    var action: BotAvatarState = .idle
    var quiet = false
    private var policy = TetrisCompanionPolicy()
    private var requestTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var bubbleTask: Task<Void, Never>?
    private var reactionPolicy = TetrisCompanionReactionPolicy()
    private var reactionEpoch = UUID()
    private var epoch = UUID()
    private var pendingText: String?
    private var lastLines = 0
    private var automaticInFlight = false

    func load(app: AppState) async {
        loading = true
        loadError = nil
        let session = app.sessionGeneration
        defer { loading = false }
        do {
            let list = try await app.api.bots().bots
            guard !Task.isCancelled, app.isCurrentSession(session) else { return }
            bots = list
            let saved = UserDefaults.standard.integer(forKey: selectionKey(app))
            if let bot = list.first(where: { $0.id == saved }) ?? list.first {
                choose(bot, app: app)
            }
        } catch {
            guard !Task.isCancelled, app.isCurrentSession(session) else { return }
            loadError = "暂时没找到伙伴，请再试一次。"
        }
    }

    func choose(_ bot: Bot, app: AppState) {
        stop()
        selected = bot
        UserDefaults.standard.set(bot.id, forKey: selectionKey(app))
        turns = []
        text = ""
        // 换伙伴不增加本局主动发言额度。
    }

    func newRound() {
        stop()
        turns = []
        text = ""
        policy = TetrisCompanionPolicy()
        policy.isQuiet = quiet
        reactionPolicy = TetrisCompanionReactionPolicy()
        lastLines = 0
    }

    func setQuiet(_ value: Bool) {
        quiet = value
        policy.isQuiet = value
        if value && automaticInFlight { stop() }
        if value { text = "" }
    }

    func synchronize(lines: Int) {
        lastLines = lines
        paused()
    }

    func observe(_ snapshot: TetrisCompanionRequest, ended: Bool, app: AppState) {
        flushPending()
        let cleared = max(0, snapshot.lines - lastLines)
        lastLines = snapshot.lines
        let event: TetrisEventKind = ended ? .ended : (cleared > 0 ? .linesCleared : .locked)
        if let reaction = reactionPolicy.consume(event: event, height: snapshot.height, cleared: cleared) {
            switch reaction.kind {
            case .idle: action = .idle
            case .smile: action = .smile
            case .success: action = .success
            case .warning: action = .warning
            case .failure: action = .failure
            }
            reactionTask?.cancel()
            reactionEpoch = UUID()
            let token = TetrisCompanionEpoch(round: reactionEpoch, partner: selected?.id ?? 0, session: app.sessionGeneration)
            reactionTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(reaction.durationMs))
                guard let self, !Task.isCancelled,
                      token.accepts(round: self.reactionEpoch, partner: self.selected?.id ?? 0, session: app.sessionGeneration) else { return }
                self.action = .idle
                self.reactionTask = nil
            }
        }
        if ended {
            send(snapshot, automatic: true, app: app)
        } else if (2...4).contains(cleared) {
            var request = snapshot
            request.cleared = cleared
            send(request, automatic: true, app: app)
        }
    }

    func send(_ request: TetrisCompanionRequest, automatic: Bool, app: AppState) {
        guard let bot = selected else { return }
        if automatic {
            let event: TetrisCompanionPolicy.Event = request.event == "end" ? .end : (request.event == "start" ? .start : .highlight)
            guard !requesting, policy.reserve(event: event, at: ProcessInfo.processInfo.systemUptime) else { return }
        } else if requesting && !automaticInFlight {
            return
        }
        let celebrating = automatic && reactionTask != nil
        stop(preservingReaction: celebrating)
        let token = TetrisCompanionEpoch(round: epoch, partner: bot.id, session: app.sessionGeneration)
        let session = app.sessionGeneration
        var payload = request
        payload.history = Array(turns.suffix(8))
        if !automatic, !request.message.isEmpty {
            turns.append(TetrisCompanionTurn(role: "user", content: request.message))
        }
        requesting = true
        automaticInFlight = automatic
        action = automatic ? (celebrating ? action : .idle) : .thinking
        let api = app.api
        requestTask = Task { [weak self] in
            do {
                let response = try await api.tetrisCompanion(botID: bot.id, request: payload)
                guard let self, !Task.isCancelled,
                      token.accepts(round: self.epoch, partner: self.selected?.id ?? 0, session: app.sessionGeneration),
                      app.isCurrentSession(session) else { return }
                let reply = automatic ? String(response.text.prefix(24)) : response.text
                if automatic && request.event == "clear" {
                    self.pendingText = reply
                } else { self.showText(reply) }
                self.turns.append(TetrisCompanionTurn(role: "assistant", content: reply))
                self.requesting = false
                self.automaticInFlight = false
                if self.reactionTask == nil { self.action = .idle }
            } catch {
                guard let self, !Task.isCancelled,
                      token.accepts(round: self.epoch, partner: self.selected?.id ?? 0, session: app.sessionGeneration),
                      app.isCurrentSession(session) else { return }
                self.error = "陪玩回应暂时没连上，你仍可以继续玩。"
                self.requesting = false
                self.automaticInFlight = false
                if self.reactionTask == nil { self.action = .idle }
            }
        }
    }

    func prepareConversation() {
        flushPending()
        // 用户主动说话优先，不能被开局或消行回应占住输入。
        if automaticInFlight { stop() }
    }

    func flushPending() {
        if let pendingText, !quiet { showText(pendingText) }
        pendingText = nil
    }

    func paused() {
        flushPending()
        reactionEpoch = UUID()
        reactionTask?.cancel()
        reactionTask = nil
        action = .idle
    }

    private func showText(_ value: String) {
        text = value
        bubbleTask?.cancel()
        let token = epoch
        bubbleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, self.epoch == token else { return }
            self.text = ""
            self.bubbleTask = nil
        }
    }

    func stop(preservingReaction: Bool = false) {
        pendingText = nil
        epoch = UUID()
        requestTask?.cancel()
        requestTask = nil
        bubbleTask?.cancel()
        bubbleTask = nil
        text = ""
        if !preservingReaction {
            reactionEpoch = UUID()
            reactionTask?.cancel()
            reactionTask = nil
            action = .idle
        }
        requesting = false
        automaticInFlight = false
        error = nil
    }

    private func selectionKey(_ app: AppState) -> String { "tetris_companion_bot_\(app.userID ?? 0)" }
}
