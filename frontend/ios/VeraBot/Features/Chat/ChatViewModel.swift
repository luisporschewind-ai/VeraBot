import SwiftUI
import VeraBotCore
import VeraBotNetworking

@MainActor
@Observable
final class ChatViewModel {
    struct Item: Identifiable {
        let id = UUID()
        let isUser: Bool
        var text: String
        var traces: [ToolTrace] = []
        var streaming = false
    }

    var bot: Bot
    private let api: any VeraBotAPI
    var items: [Item] = []
    var sending = false
    var errorText: String?
    var scrollTick = 0

    init(bot: Bot, api: any VeraBotAPI) {
        self.bot = bot
        self.api = api
    }

    func load() async {
        do {
            let r = try await api.messages(botID: bot.id)
            items = r.messages.map { Item(isUser: $0.role == "user", text: $0.content, traces: $0.traces ?? []) }
            if items.isEmpty {
                items = [Item(isUser: false, text: "你好，我是 **\(bot.name)**。试试：「石家庄天气怎么样」「明早 9 点提醒我开会」")]
            }
            scrollTick += 1
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// BUG-07：回复为空时不再在错误前拼接空行
    private func appendError(_ msg: String, at idx: Int) {
        let t = items[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].text = t.isEmpty ? "⚠️ \(msg)" : items[idx].text + "\n\n⚠️ \(msg)"
    }

    func clear() async {
        _ = try? await api.clearMessages(botID: bot.id)
        await load()
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return }
        sending = true
        errorText = nil
        items.append(Item(isUser: true, text: trimmed))
        items.append(Item(isUser: false, text: "", streaming: true))
        let idx = items.count - 1
        scrollTick += 1
        do {
            for try await event in api.chatStream(botID: bot.id, message: trimmed) {
                switch event {
                case .delta(let t):
                    items[idx].text += t
                case .toolStart(let trace):
                    items[idx].traces.append(trace)
                case .toolResult(let trace):
                    if let i = items[idx].traces.firstIndex(where: { $0.id == trace.id }) {
                        items[idx].traces[i] = trace
                    } else {
                        items[idx].traces.append(trace)
                    }
                case .error(let msg):
                    appendError(msg, at: idx)
                case .done:
                    break
                }
                scrollTick += 1
            }
        } catch let e as APIError where e.status == 429 {
            appendError("今日 Token 额度已用完，请明天再试（可在「设置 › 用量」查看今日用量）", at: idx)
        } catch {
            appendError(error.localizedDescription, at: idx)
        }
        if items[idx].text.isEmpty && items[idx].traces.isEmpty { items[idx].text = "（无回复）" }
        items[idx].streaming = false
        sending = false
        scrollTick += 1
    }
}
