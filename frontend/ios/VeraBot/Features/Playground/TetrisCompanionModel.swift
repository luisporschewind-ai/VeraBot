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
        lastLines = 0
    }

    func setQuiet(_ value: Bool) {
        quiet = value
        policy.isQuiet = value
        if value && automaticInFlight { stop() }
        if value { text = "" }
    }

    func observe(_ snapshot: TetrisCompanionRequest, ended: Bool, app: AppState) {
        flushPending()
        let cleared = max(0, snapshot.lines - lastLines)
        lastLines = snapshot.lines
        if cleared > 0 {
            action = .success
            reactionTask?.cancel()
            reactionTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.action = .idle
            }
        }
        if ended {
            send(snapshot, automatic: true, app: app)
        } else if cleared >= 2 {
            var request = snapshot
            request.cleared = cleared
            send(request, automatic: true, app: app)
        }
    }

    func send(_ request: TetrisCompanionRequest, automatic: Bool, app: AppState) {
        guard let bot = selected else { return }
        if automatic {
            guard !requesting, policy.reserve(at: Date().timeIntervalSince1970) else { return }
        } else if requesting && !automaticInFlight {
            return
        }
        let celebrating = automatic && action == .success
        stop(preservingReaction: celebrating)
        let token = epoch
        let session = app.sessionGeneration
        var payload = request
        payload.history = Array(turns.suffix(8))
        if !automatic, !request.message.isEmpty {
            turns.append(TetrisCompanionTurn(role: "user", content: request.message))
        }
        requesting = true
        automaticInFlight = automatic
        action = automatic ? (celebrating ? .success : .idle) : .thinking
        let api = app.api
        requestTask = Task { [weak self] in
            do {
                let response = try await api.tetrisCompanion(botID: bot.id, request: payload)
                guard let self, !Task.isCancelled, self.epoch == token, app.isCurrentSession(session) else { return }
                if automatic && request.event == "clear" {
                    self.pendingText = response.text
                } else { self.text = response.text }
                self.turns.append(TetrisCompanionTurn(role: "assistant", content: response.text))
                self.requesting = false
                self.automaticInFlight = false
                if self.action != .success { self.action = .idle }
            } catch {
                guard let self, !Task.isCancelled, self.epoch == token, app.isCurrentSession(session) else { return }
                self.error = "陪玩回应暂时没连上，你仍可以继续玩。"
                self.requesting = false
                self.automaticInFlight = false
                if self.action != .success { self.action = .idle }
            }
        }
    }

    func prepareConversation() {
        flushPending()
        // 用户主动说话优先，不能被开局或消行回应占住输入。
        if automaticInFlight { stop() }
    }

    func flushPending() {
        if let pendingText, !quiet { text = pendingText }
        pendingText = nil
    }

    func stop(preservingReaction: Bool = false) {
        pendingText = nil
        epoch = UUID()
        requestTask?.cancel()
        requestTask = nil
        if !preservingReaction { reactionTask?.cancel(); action = .idle }
        requesting = false
        automaticInFlight = false
        error = nil
    }

    private func selectionKey(_ app: AppState) -> String { "tetris_companion_bot_\(app.userID ?? 0)" }
}
