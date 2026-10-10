import Foundation
import VeraBotCore

enum BotAvatarState: String, CaseIterable, Identifiable {
    case idle, bored, waiting
    case waitingWrap = "waiting-wrap"
    case input, send, success, failure, warning, inspect, blocked, error, surprise, sleep, wake, love, random
    case starEyes = "star-eyes"
    case smile = "smile"
    case thinking, recalling, working, delegating, replying
    case awaitingConfirmation = "awaiting-confirmation"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .idle: "正常"
        case .bored: "发呆"
        case .waiting: "等待"
        case .waitingWrap: "等待 · 环绕"
        case .input: "输入"
        case .send: "发送 / 点头"
        case .success: "成功"
        case .failure: "失败"
        case .warning: "警告"
        case .inspect: "审视"
        case .blocked: "内容阻止"
        case .error: "系统错误"
        case .surprise: "惊讶"
        case .sleep: "睡着"
        case .wake: "醒来"
        case .love: "喜欢"
        case .random: "随机"
        case .thinking: "思考"
        case .recalling: "召回记忆"
        case .working: "执行工具"
        case .delegating: "委派"
        case .replying: "回复"
        case .awaitingConfirmation: "等待确认"
        case .starEyes: "星星眼"
        case .smile: "微笑 · 月牙眼"
        }
    }
    var detail: String {
        switch self {
        case .idle: "自然眨眼，偶尔看向四周"
        case .bored: "抬眼看向左上、右上，再回到中央"
        case .waiting: "双眼交叉绕行，随前后位置改变大小"
        case .waitingWrap: "双眼绕过头部，在背面隐去再出现"
        case .input: "双眼收成竖向光标，同步闪烁"
        case .send: "连续点两次头，第二次缓缓回正"
        case .success: "笑眼和短促的轻弹"
        case .failure: "眼睑下垂，表示任务未完成"
        case .warning: "近眼放大、远眼收窄，眼睑下压再抬起"
        case .inspect: "眯起双眼，上下观察后重新睁开"
        case .blocked: "收紧眼神，轻摇一次"
        case .error: "双眼左右扫动，头部随后左右摇动"
        case .surprise: "先收缩，再睁大双眼"
        case .sleep: "双眼合上，头部轻垂"
        case .wake: "睁开眼睛，重新抬头"
        case .love: "两只眼睛各变为一颗心，轻跳后回正"
        case .random: "双眼滚动，先后减速并回弹停下"
        case .thinking: "向左上思考，天线随头部轻轻抬起"
        case .recalling: "左右回望，天线跟随回忆的节奏"
        case .working: "专注执行，双眼与天线按节拍微动"
        case .delegating: "向右观察并点头，天线随交接方向偏移"
        case .replying: "双眼轻动，头部与天线随回复节奏点动"
        case .awaitingConfirmation: "面向你等待回应，轻点头提示确认"
        case .starEyes: "双眼变成圆润星星，明亮地轻轻闪烁"
        case .smile: "双眼弯成圆润月牙，轻轻笑起后自然睁开"
        }
    }
    enum Category { case original, work }
    var category: Category { [.thinking,.recalling,.working,.delegating,.replying,.awaitingConfirmation].contains(self) ? .work : .original }
    var continuous: Bool { self == .input || category == .work }
    var descriptor: BotAvatarStateDescriptor {
        let loop: Double? = switch self {
        case .thinking,.delegating,.awaitingConfirmation: 2400
        case .recalling: 2800
        case .working: 1800
        case .replying: 1200
        default: nil
        }
        let antenna: Double? = switch self {
        case .input,.thinking,.delegating,.replying: 1200
        case .send,.warning: 1000
        case .success: 1100
        case .blocked,.working: 900
        case .error,.surprise: 800
        case .recalling: 1400
        case .awaitingConfirmation: 2400
        default: nil
        }
        let length = RobotAvatarMotion.duration(self)
        let demo = category == .work ? 4800 : (length.isFinite ? length + 800 : (self == .input ? 3000 : 2500))
        return .init(title:title,detail:detail,category:category,continuous:continuous,loopMS:loop,demoMS:demo,antennaPeriodMS:antenna)
    }
}

/// 将会话执行状态投影为新版头像动作；终态也保留短暂的情绪反馈。
extension BotAvatarState {
    init(_ state: ExecutionState) {
        switch state {
        case .idle: self = .idle
        case .recalling: self = .recalling
        case .thinking: self = .thinking
        case .callingTool: self = .working
        case .delegating: self = .delegating
        case .replying: self = .replying
        case .blocked: self = .blocked
        case .awaitingConfirmation: self = .awaitingConfirmation
        case .completed: self = .success
        case .failed: self = .error
        }
    }
}

typealias RobotAvatarAction = BotAvatarState

struct BotAvatarStateDescriptor {
    let title: String
    let detail: String
    let category: BotAvatarState.Category
    let continuous: Bool
    let loopMS: Double?
    let demoMS: Double
    let antennaPeriodMS: Double?
}
