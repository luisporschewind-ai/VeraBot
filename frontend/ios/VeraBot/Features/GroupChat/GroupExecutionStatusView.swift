import SwiftUI
import VeraBotCore
import VeraBotData

struct GroupExecutionStatusView: View {
    let model: GroupChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        if model.hasUnconfirmedInput {
            HStack {
                Text("正在确认上一条消息是否已发送").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("确认发送状态") {model.recoverPendingSubmission()}.font(.caption).disabled(model.sending)
            }
        }
        if let task = model.execution.snapshot.task,
           task.state != .completed {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: symbol(for: task.state)).foregroundStyle(task.state == .failed ? .orange : .secondary)
                    Text(label(for: task.state)).font(.caption.weight(.semibold))
                    if let owner = model.group.members.first(where: { $0.id == task.ownerMemberID }) {
                        Text("· \(owner.name)负责").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if model.executionSyncPending {
                    Text("进度待同步").font(.caption2).foregroundStyle(.secondary)
                }
                Text(task.goal).font(.footnote).lineLimit(2).foregroundStyle(.primary)
                if task.state == .awaitingUser, let clarification = model.execution.snapshot.clarification {
                    if let owner = model.group.members.first(where: { $0.id == clarification.ownerMemberID }) {
                        Text("后续回答会继续由 \(owner.name) 跟进").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if task.state.canResume {
                    Button("继续任务") { model.resume() }.font(.caption.weight(.medium)).disabled(model.sending)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        }
    }

    private func label(for status: GroupTaskStatus) -> String {
        switch status {
        case .queued: "等待处理"
        case .running: "正在处理"
        case .awaitingUser: "需要你补充信息"
        case .interrupted: "任务中断，可继续"
        case .failed: "任务遇到问题，可重试"
        case .completed: "已完成"
        case .stopped: "已停止"
        }
    }

    private func symbol(for status: GroupTaskStatus) -> String {
        switch status {
        case .queued: "clock"
        case .running: "arrow.trianglehead.2.clockwise.rotate.90"
        case .awaitingUser: "questionmark.bubble"
        case .interrupted: "pause.circle"
        case .failed: "exclamationmark.circle"
        case .completed: "checkmark.circle"
        case .stopped: "stop.circle"
        }
    }
}
