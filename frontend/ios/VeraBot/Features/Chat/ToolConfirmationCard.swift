import SwiftUI
import VeraBotCore

/// 对话内的 MCP 工具确认卡片（M3）。所见即所执行：展示冻结参数，「执行」才调用远程。
struct ToolConfirmationCard: View {
    let action: PendingAction
    let vm: ChatViewModel

    private var busy: Bool { vm.actionBusy.contains(action.id) }
    private var current: PendingAction { vm.actionStates[action.id] ?? action }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch current.status {
            case "pending":
                pendingBody
            case "done":
                Label(current.result ?? "已执行", systemImage: "checkmark.circle")
                    .font(.footnote.bold()).foregroundStyle(Color.brand)
            case "cancelled":
                Label("已取消", systemImage: "xmark.circle").font(.footnote).foregroundStyle(.secondary)
            case "expired":
                Label("已过期", systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
            case "failed", "unknown":
                Label(current.result ?? "执行失败", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            default:
                Label(current.status, systemImage: "questionmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var pendingBody: some View {
        Label("需要你确认", systemImage: "hand.raised").font(.footnote.bold())
        Text(titleLine).font(.subheadline)
        Label(current.toolRisk.label, systemImage: riskIcon)
            .font(.caption2).foregroundStyle(.secondary)
        if !current.warnings.isEmpty {
            ForEach(current.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        let pairs = current.arguments?.argumentPairs ?? []
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(pairs, id: \.0) { key, value in
                    HStack(alignment: .top, spacing: 6) {
                        Text(key).font(.caption2.bold()).foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        Text(value).font(.caption).textSelection(.enabled)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.insetFill, in: RoundedRectangle(cornerRadius: 8))
        } else if current.argsUnavailable == true {
            Text("参数无法解密（密钥缺失）").font(.caption).foregroundStyle(.orange)
        }
        if let exp = current.expiresAt {
            Text("过期：\(exp)").font(.caption2).foregroundStyle(.secondary)
        }
        HStack(spacing: 8) {
            Button("执行") { Task { await vm.confirmAction(current.id) } }
                .prominentButtonStyle()
                .accessibilityLabel("执行此操作")
            Button("取消", role: .cancel) { Task { await vm.cancelAction(current.id) } }
                .glassButtonStyle()
                .accessibilityLabel("取消此操作")
            if busy { ProgressView() }
        }
        .controlSize(.small)
        .disabled(busy)
    }

    private var titleLine: String {
        let server = current.server ?? "外部服务"
        let tool = current.label ?? current.tool ?? "工具"
        return "\(server) · \(tool)"
    }

    private var riskIcon: String {
        switch current.toolRisk {
        case .destructive: return "trash"
        case .send: return "paperplane"
        case .write: return "pencil"
        default: return "lock"
        }
    }
}
