// 执行状态机：由后端 SSE 事件推导 Bot 当前在做什么（纯数据，无 UI、无网络）。
// 设计与对照表见 docs/design/EXECUTION_STATE.md。
import Foundation

/// Bot 一轮回复的执行状态。
public enum ExecutionState: Sendable, Hashable {
    /// 没有进行中的回复。
    case idle
    /// 已发送，等待模型输出（首字之前、或工具返回后模型继续处理）。
    case thinking
    /// 正在调用工具（`ask_bot` 以外，含记忆工具），值为后端工具名。
    case callingTool(name: String)
    /// 正在委派另一个 Bot（`ask_bot`），值为目标 Bot 昵称（缺失时为空串）。
    case delegating(botName: String)
    /// 正在输出回复文字。
    case replying
    /// 回复已结束，本轮产生了待用户确认的记忆卡片。
    case awaitingConfirmation
    /// 回复正常结束。
    case completed
    /// 本轮出错（后端 error 事件、HTTP 错误或网络错误）。
    case failed(message: String)

    /// 回复是否仍在进行（thinking / callingTool / delegating / replying）。
    public var isActive: Bool {
        switch self {
        case .thinking, .callingTool, .delegating, .replying: true
        case .idle, .awaitingConfirmation, .completed, .failed: false
        }
    }
}

/// 驱动状态机的输入。前 5 种与后端 SSE 事件一一对应，其余由客户端产生。
public enum ExecutionEvent: Sendable, Hashable {
    /// 用户发出一条消息（请求开始）。
    case sent
    /// SSE `delta`。
    case delta(String)
    /// SSE `tool_start`（result 为 nil）。
    case toolStart(ToolTrace)
    /// SSE `tool_result`。
    case toolResult(ToolTrace)
    /// SSE `error`，或客户端捕获的 HTTP / 网络错误。
    case error(String)
    /// SSE `done`。
    case done
    /// 流结束（无论是否收到 done）；仍在进行时按 done 处理。
    case streamEnded
    /// 用户处理了某张记忆确认卡片（记住 / 不用 / 已忘掉）。
    case confirmationResolved(memoryID: Int)
    /// 回到空闲（清空对话、离开页面、完成提示展示结束等）。
    case reset
}

/// 执行状态机。值类型，`send(_:)` 原地更新；同一输入序列总得到同一结果。
public struct ExecutionStateMachine: Sendable, Hashable {
    public static let delegationToolName = "ask_bot"

    public private(set) var state: ExecutionState = .idle
    private struct OpenTool: Sendable, Hashable {
        let id: String
        let state: ExecutionState
    }
    /// 已开始、尚未返回的工具调用（按开始顺序）。
    private var openTools: [OpenTool] = []
    /// 本轮待确认的记忆提议 id。
    public private(set) var pendingConfirmations: Set<Int> = []

    public init() {}

    public mutating func send(_ event: ExecutionEvent) {
        switch event {
        case .sent:
            openTools = []
            pendingConfirmations = []
            state = .thinking

        case .delta(let text):
            guard state.isActive, !text.isEmpty else { return }
            state = .replying

        case .toolStart(let trace):
            guard state.isActive else { return }
            let next: ExecutionState = trace.name == Self.delegationToolName
                ? .delegating(botName: trace.args?["bot_name"]?.text ?? "")
                : .callingTool(name: trace.name)
            openTools.removeAll { $0.id == trace.id }
            openTools.append(OpenTool(id: trace.id, state: next))
            state = next

        case .toolResult(let trace):
            guard state.isActive else { return }
            openTools.removeAll { $0.id == trace.id }
            if let p = trace.memoryProposal, p.isCard, let id = p.memoryID {
                pendingConfirmations.insert(id)
            }
            // 还有未返回的工具时显示最近开始的那个；否则模型继续处理
            state = openTools.last?.state ?? .thinking

        case .error(let message):
            guard state.isActive else { return }
            openTools = []
            state = .failed(message: message)

        case .done, .streamEnded:
            guard state.isActive else { return }
            openTools = []
            state = pendingConfirmations.isEmpty ? .completed : .awaitingConfirmation

        case .confirmationResolved(let id):
            guard pendingConfirmations.remove(id) != nil else { return }
            if state == .awaitingConfirmation, pendingConfirmations.isEmpty { state = .idle }

        case .reset:
            openTools = []
            pendingConfirmations = []
            state = .idle
        }
    }

    /// 便捷：按顺序应用一串事件。
    public mutating func send<S: Sequence>(contentsOf events: S) where S.Element == ExecutionEvent {
        for e in events { send(e) }
    }
}
