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
    /// 对话中记忆确认卡片的服务器状态（memory_id → 最新 Memory；nil 值 = 已不存在）
    var memoryStates: [Int: Memory?] = [:]
    /// 本机刚处理过、服务器上已删除的提议（如「忘掉」确认后提议本身被删除）：memory_id → 结果文案
    var memoryOutcomes: [Int: String] = [:]
    var memoryBusy: Set<Int> = []
    var memoryConfirmTick = 0   // 触感反馈触发器：确认记住 +1

    init(bot: Bot, api: any VeraBotAPI) {
        self.bot = bot
        self.api = api
    }

    func load() async {
        do {
            let r = try await api.messages(botID: bot.id)
            items = r.messages.map { Item(isUser: $0.role == "user", text: $0.content, traces: $0.traces ?? []) }
            if items.isEmpty {
                items = [Item(isUser: false, text: "你好，我是 **\(bot.name)**。试试：「石家庄天气怎么样」「明早 9 点提醒我开会」「记住我不吃香菜」")]
            }
            scrollTick += 1
        } catch {
            errorText = error.localizedDescription
        }
        await refreshMemoryStates()
    }

    // MARK: - 记忆确认卡片（remember / forget_memory 的 trace）

    private var proposalIDs: [Int] {
        items.flatMap { $0.traces.compactMap { $0.memoryProposal }.filter(\.isCard).compactMap(\.memoryID) }
    }

    /// 批量刷新卡片状态（历史重载 / 跨设备都以服务器为准）。不存在的 id 记为 nil（已删除）。
    func refreshMemoryStates() async {
        let ids = Array(Set(proposalIDs)).sorted().suffix(50)
        guard !ids.isEmpty else { return }
        do {
            let r = try await api.memories(MemoryQuery(statuses: [.proposed, .candidate, .active, .rejected, .expired],
                                                       ids: Array(ids)))
            var next: [Int: Memory?] = [:]
            for id in ids { next[id] = .some(nil) }
            for m in r.memories { next[m.id] = m }
            memoryStates.merge(next) { _, new in new }
        } catch {
            // 刷新失败时保留卡片当时的状态（proposed），用户仍可点按，服务器会返回真实结果
        }
    }

    func confirmMemory(_ id: Int, content: String? = nil) async {
        memoryBusy.insert(id)
        defer { memoryBusy.remove(id) }
        do {
            switch try await api.confirmMemory(id: id, content: content) {
            case .memory(let m):
                memoryStates[id] = m
            case .deleted:
                memoryStates[id] = .some(nil)
                memoryOutcomes[id] = "已忘掉"
            }
            memoryConfirmTick += 1
        } catch {
            await handleMemoryError(error, id: id)
        }
    }

    func rejectMemory(_ id: Int) async {
        memoryBusy.insert(id)
        defer { memoryBusy.remove(id) }
        do {
            _ = try await api.rejectMemory(id: id)
            memoryOutcomes[id] = "已忽略"
            await refreshMemoryStates()
        } catch {
            await handleMemoryError(error, id: id)
        }
    }

    /// 422（编辑后的内容未通过策略）显示服务器文案；404 / 409 / 410 以服务器最新状态为准。
    private func handleMemoryError(_ error: Error, id: Int) async {
        if let e = error as? APIError, [404, 409, 410].contains(e.status) {
            await refreshMemoryStates()
            if e.status == 404 { memoryStates[id] = .some(nil) }
        } else {
            errorText = error.localizedDescription
        }
    }

    /// BUG-07：回复为空时不再在错误前拼接空行
    private func appendError(_ msg: String, at idx: Int) {
        let t = items[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].text = t.isEmpty ? "⚠️ \(msg)" : items[idx].text + "\n\n⚠️ \(msg)"
    }

    /// 清空对话；includeMemories = true 时同时删除该 Bot 的「本 Bot 记忆」与对话摘要（共享资料保留）。
    func clear(includeMemories: Bool = false) async {
        _ = try? await api.clearMessages(botID: bot.id, includeMemories: includeMemories)
        memoryStates = [:]
        memoryOutcomes = [:]
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
            appendError("今日额度已用完，请明天再试（可在「设置 › 用量」查看今日用量）", at: idx)
        } catch {
            appendError(error.localizedDescription, at: idx)
        }
        if items[idx].text.isEmpty && items[idx].traces.isEmpty { items[idx].text = "（无回复）" }
        items[idx].streaming = false
        sending = false
        scrollTick += 1
        if items[idx].traces.contains(where: { $0.memoryProposal?.isCard == true }) {
            await refreshMemoryStates()
        }
    }
}
