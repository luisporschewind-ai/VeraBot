// 把头像需要的两段计时收成可测试的命令：状态机本身仍然没有计时器。
// 界面（ChatViewModel）按命令启动 / 取消 Task。reset、提前离开 blocked、再次受阻都会发出取消。
import Foundation

public enum ExecutionTimerCommand: Equatable, Sendable {
    /// 进入「短暂受阻」。serial 对应 `ExecutionStateMachine.blockedSerial`。
    case startBlocked(serial: Int)
    /// 取消尚未触发的受阻计时（reset、离开 blocked、或被更新的 serial 替换）。
    case cancelBlocked
    /// 正常结束，等待 `completedIdleDelay` 后回到空闲。
    case startIdle
    /// 取消「完成后回空闲」（reset、发出新消息、或已经回到空闲）。
    case cancelIdle
}

/// 执行状态机 + 头像计时策略。`send` / `blockedFired` / `idleFired` 返回界面要执行的命令。
public struct ExecutionAvatarController: Sendable {
    public private(set) var machine = ExecutionStateMachine()
    private var blockedArmed: Int?
    private var idleArmed = false

    public init() {}

    public var state: ExecutionState { machine.state }

    public mutating func send(_ event: ExecutionEvent) -> [ExecutionTimerCommand] {
        machine.send(event)
        return reconcile()
    }

    /// 受阻展示时间到。计时器已被取消（serial 不再是当前这一次）时什么都不做。
    public mutating func blockedFired(serial: Int) -> [ExecutionTimerCommand] {
        guard blockedArmed == serial else { return [] }
        machine.send(.blockedElapsed(serial: serial))
        return reconcile()
    }

    /// 完成后的空闲等待结束。计时器已被取消时什么都不做。
    public mutating func idleFired() -> [ExecutionTimerCommand] {
        guard idleArmed else { return [] }
        machine.send(.reset)
        return reconcile()
    }

    private mutating func reconcile() -> [ExecutionTimerCommand] {
        var commands: [ExecutionTimerCommand] = []
        let nextBlocked: Int? = if case .blocked = machine.state { machine.blockedSerial } else { nil }
        if nextBlocked != blockedArmed {
            if blockedArmed != nil { commands.append(.cancelBlocked) }
            if let serial = nextBlocked { commands.append(.startBlocked(serial: serial)) }
            blockedArmed = nextBlocked
        }
        let nextIdle = machine.state == .completed
        if nextIdle != idleArmed {
            commands.append(nextIdle ? .startIdle : .cancelIdle)
            idleArmed = nextIdle
        }
        return commands
    }
}
