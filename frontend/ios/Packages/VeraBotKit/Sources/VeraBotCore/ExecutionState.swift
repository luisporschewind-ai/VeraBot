// 执行状态机：由后端 SSE 事件推导 Bot 当前在做什么（纯数据，无 UI、无网络、无计时器）。
// 设计与对照表见 docs/design/EXECUTION_STATE.md。
import Foundation

// MARK: - SSE status 事件

/// SSE `status` 事件（后端 agents/runtime.py `status_data`）。字段名与后端逐一对应，契约测试 STAT-08 会读取本文件核对。
public struct ChatStatus: Codable, Sendable, Hashable {
    public enum Phase: String, Codable, Sendable, CaseIterable {
        case recalling
        case thinking
        case tool
    }

    /// 原始 phase；未知值保留原文（新后端可能新增阶段），`knownPhase` 为 nil。
    public let phase: String
    public let depth: Int
    public let botName: String?
    public let tool: String?
    public let parentID: String?

    enum CodingKeys: String, CodingKey {
        case phase
        case depth
        case botName = "bot_name"
        case tool
        case parentID = "parent_id"
    }

    public init(phase: String, depth: Int = 0, botName: String? = nil, tool: String? = nil, parentID: String? = nil) {
        self.phase = phase
        self.depth = depth
        self.botName = botName
        self.tool = tool
        self.parentID = parentID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decodeIfPresent(String.self, forKey: .phase) ?? ""
        depth = try c.decodeIfPresent(Int.self, forKey: .depth) ?? 0
        botName = try c.decodeIfPresent(String.self, forKey: .botName)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
    }

    public var knownPhase: Phase? { Phase(rawValue: phase) }
}

// MARK: - 状态

/// 委派内部进度：被委派链上当前正在工作的 Bot（来自 status 事件）。
public struct DelegationProgress: Sendable, Hashable {
    public let botName: String
    public let depth: Int
    /// 正在调用的工具；nil = 正在等待模型（思考）。
    public let tool: String?

    public init(botName: String, depth: Int, tool: String? = nil) {
        self.botName = botName
        self.depth = depth
        self.tool = tool
    }
}

/// Bot 一轮回复的执行状态。
public enum ExecutionState: Sendable, Hashable {
    /// 没有进行中的回复。
    case idle
    /// 召回记忆 / 准备上下文（status recalling）。
    case recalling
    /// 等待模型输出（首字之前、或工具返回后模型继续处理）。
    case thinking
    /// 正在调用工具（`ask_bot` 以外，含记忆工具），值为后端工具名。
    case callingTool(name: String)
    /// 正在委派（`ask_bot`）：目标 Bot 昵称（缺失为空串）+ 最近一条内部进度（尚未收到为 nil）。
    case delegating(botName: String, progress: DelegationProgress?)
    /// 正在输出回复文字。
    case replying
    /// 短暂受阻：工具 / 委派被拒绝或失败（tool_result 带 error）。显示 `blockedDisplayDuration` 后回到原流程。
    case blocked(code: String?, message: String)
    /// 回复已结束，本轮产生了待用户确认的记忆卡片。
    case awaitingConfirmation
    /// 回复正常结束。
    case completed
    /// 整轮出错（后端 error 事件、HTTP 错误或网络错误）。
    case failed(message: String)

    /// 回复是否仍在进行（含短暂受阻）。
    public var isActive: Bool {
        switch self {
        case .recalling, .thinking, .callingTool, .delegating, .replying, .blocked: true
        case .idle, .awaitingConfirmation, .completed, .failed: false
        }
    }
}

/// 驱动状态机的输入。delta / toolStart / toolResult / status / error / done 与后端 SSE 事件一一对应，其余由客户端产生。
public enum ExecutionEvent: Sendable, Hashable {
    /// 用户发出一条消息（请求开始）。
    case sent
    /// SSE `delta`。
    case delta(String)
    /// SSE `tool_start`（result 为 nil）。
    case toolStart(ToolTrace)
    /// SSE `tool_result`。
    case toolResult(ToolTrace)
    /// SSE `status`。
    case status(ChatStatus)
    /// SSE `error`，或客户端捕获的 HTTP / 网络错误。
    case error(String)
    /// SSE `done`。
    case done
    /// SSE `notification`。不改变执行状态，只让界面去刷新收件箱。
    case notification
    /// 流结束（无论是否收到 done）；仍在进行时按 done 处理。
    case streamEnded
    /// 「短暂受阻」展示时间到（客户端计时后发送，serial 取自 `blockedSerial`）。
    case blockedElapsed(serial: Int)
    /// 用户处理了某张记忆确认卡片（记住 / 不用 / 已忘掉）。
    case confirmationResolved(memoryID: Int)
    /// 回到空闲（清空对话、离开页面、完成提示展示结束等）。
    case reset
}

// MARK: - 状态机

/// 执行状态机。值类型，`send(_:)` 原地更新；同一输入序列总得到同一结果。
public struct ExecutionStateMachine: Sendable, Hashable {
    public static let delegationToolName = "ask_bot"
    /// 「短暂受阻」建议展示时长（由界面层计时，然后发送 `.blockedElapsed`）。
    public static let blockedDisplayDuration: Duration = .milliseconds(1200)
    /// 正常结束后头像保持「已完成」的时长，然后界面发送 `.reset` 回到空闲。
    public static let completedIdleDelay: Duration = .milliseconds(1500)

    private struct OpenTool: Sendable, Hashable {
        let id: String
        var state: ExecutionState
    }

    public private(set) var state: ExecutionState = .idle
    /// 已开始、尚未返回的工具调用（按开始顺序）。
    private var openTools: [OpenTool] = []
    /// 本轮待确认的记忆提议 id。
    public private(set) var pendingConfirmations: Set<Int> = []
    /// 每进入一次 blocked +1；`.blockedElapsed` 只对最新一次生效。
    public private(set) var blockedSerial = 0
    /// blocked 结束后回到的状态。
    private var resumeState: ExecutionState = .thinking

    public init() {}

    /// 当前流程（不考虑 blocked）应处的状态：最近开始且未返回的工具，否则 thinking。
    private var flowState: ExecutionState { openTools.last?.state ?? .thinking }

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
                ? .delegating(botName: trace.args?["bot_name"]?.text ?? "", progress: nil)
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
            if let failure = Self.failure(of: trace) {
                blockedSerial += 1
                resumeState = flowState
                state = .blocked(code: failure.code, message: failure.message)
            } else {
                state = flowState
            }

        case .status(let s):
            guard state.isActive else { return }
            switch s.knownPhase {
            case .recalling:
                // 只在首字 / 工具之前有意义
                if state == .thinking { state = .recalling }
            case .thinking, .tool:
                guard s.depth >= 1, let parent = s.parentID,
                      let i = openTools.firstIndex(where: { $0.id == parent }),
                      case .delegating(let target, _) = openTools[i].state else { return }
                let progress = DelegationProgress(botName: s.botName ?? target, depth: s.depth,
                                                  tool: s.knownPhase == .tool ? s.tool : nil)
                openTools[i].state = .delegating(botName: target, progress: progress)
                if case .blocked = state {
                    resumeState = flowState
                } else {
                    state = flowState
                }
            case nil:
                return   // 未知阶段：忽略（向前兼容）
            }

        case .blockedElapsed(let serial):
            guard case .blocked = state, serial == blockedSerial else { return }
            state = resumeState

        case .error(let message):
            guard state.isActive else { return }
            openTools = []
            state = .failed(message: message)

        case .notification:
            return

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

    /// tool_result 是否表示工具 / 委派被拒绝或失败：result 带非空 `error`（`code` 可选，
    /// 如委派的 self / loop / not_in_allowlist / target_refuses / turn_cap / budget，权限的 tool_not_allowed / max_depth …）。
    public static func failure(of trace: ToolTrace) -> (code: String?, message: String)? {
        guard let r = trace.result, let e = r["error"], e != .null else { return nil }
        let message = e.text
        guard !message.isEmpty else { return nil }
        let code = r["code"].flatMap { $0 == .null ? nil : $0.text }
        return (code?.isEmpty == true ? nil : code, message)
    }
}
