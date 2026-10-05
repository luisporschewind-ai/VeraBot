import SwiftUI
import VeraBotCore

/// 对话内的记忆确认卡片（remember / forget_memory 提议）。卡片是唯一的写入入口：模型说「已记住」不算数。
/// 系统原生控件 + Theme（sectionFill、prominentButtonStyle / glassButtonStyle），不加自定义动画。
struct MemoryProposalCard: View {
    let proposal: MemoryProposal
    let botName: String
    let vm: ChatViewModel

    @State private var editing = false
    @State private var draft = ""

    private var id: Int { proposal.memoryID ?? 0 }
    private var busy: Bool { vm.memoryBusy.contains(id) }
    /// 服务器最新状态：nil = 未刷新（按提议当时的状态显示）；.some(nil) = 已不存在
    private var server: Memory?? { vm.memoryStates[id] }
    private var current: Memory? { server ?? nil }
    private var content: String {
        if let c = current?.content, !c.isEmpty { return c }
        return proposal.content
    }
    private var targetContent: String? { current?.targetContent ?? proposal.targetContent }
    private var sensitive: Bool { current?.sensitive ?? proposal.sensitive }
    private var scopeIsGlobal: Bool { (current?.scope ?? proposal.scope) == .global }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .pending:
                pendingBody
            case .remembered:
                Label("已记住", systemImage: "checkmark.circle").font(.footnote.bold()).foregroundStyle(Color.brand)
                Text(content).font(.subheadline)
                NavigationLink {
                    MemoryListView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Text("在「Vera 了解的你」中查看").font(.footnote)
                }
            case .done(let text):
                Label(text, systemImage: "brain").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .alert("编辑后记住", isPresented: $editing) {
            TextField("记忆内容", text: $draft)
            Button("记住") {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                Task { await vm.confirmMemory(id, content: text) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("修改后的内容会再次检查；密码、验证码、证件号、卡号不会被记住。")
        }
    }

    private enum CardState: Equatable { case pending, remembered, done(String) }

    private var state: CardState {
        if let outcome = vm.memoryOutcomes[id] { return .done(outcome) }
        guard let server else { return .pending }          // 尚未刷新：按提议当时的状态
        guard let m = server else {
            return .done(proposal.action == .delete ? "这条提议已处理" : "这条记忆已删除")
        }
        switch m.status {
        case .proposed, .candidate: return .pending
        case .active: return proposal.action == .delete ? .done("已处理") : .remembered
        case .rejected: return .done("已忽略")
        case .expired: return .done("已过期")
        case .unknown: return .done("已处理")
        }
    }

    private var title: String {
        // 风格校准（M2）：来源是「再短一点」这类要求或 👎 聚合，标题问的是「以后」而不是「记住吗」
        if proposal.action == .create, proposal.type == .style { return "以后都这样回答吗？" }
        switch proposal.action {
        case .update: return "要更新这条记忆吗？"
        case .delete: return "要忘掉这条吗？"
        default: return "要我记住吗？"
        }
    }

    @ViewBuilder private var pendingBody: some View {
        Label(title, systemImage: "brain").font(.footnote.bold())
        if proposal.action == .delete {
            Text(targetContent ?? "（记忆内容）").font(.subheadline)
        } else {
            Text(content).font(.subheadline)
            if proposal.action == .update, let old = targetContent {
                Text("原来：\(old)").font(.caption).foregroundStyle(.secondary)
            }
        }
        HStack(spacing: 6) {
            Label(scopeIsGlobal ? "所有 Bot 可用" : "仅 \(botName) 可用",
                  systemImage: scopeIsGlobal ? "person.2" : "person")
            if sensitive {
                Label("敏感 · 加密保存", systemImage: "lock")
            }
        }
        .font(.caption2).foregroundStyle(.secondary)
        HStack(spacing: 8) {
            Button(proposal.action == .delete ? "忘掉" : "记住") {
                Task { await vm.confirmMemory(id) }
            }
            .prominentButtonStyle()
            .accessibilityLabel(proposal.action == .delete ? "忘掉这条记忆" : "记住这条记忆")
            Button("不用") { Task { await vm.rejectMemory(id) } }
                .glassButtonStyle()
                .accessibilityLabel(proposal.action == .delete ? "保留这条记忆" : "不用记住")
            if proposal.action != .delete {
                Menu {
                    Button { draft = content; editing = true } label: { Label("编辑后记住", systemImage: "pencil") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多")
            }
            if busy { ProgressView() }
        }
        .controlSize(.small)
        .disabled(busy)
    }
}

/// 不弹卡片的记忆工具结果（已在记忆中 / 被拒绝保存 / 未授权）：一行次要文字。
struct MemoryToolNote: View {
    let proposal: MemoryProposal

    var body: some View {
        let text = proposal.summary
        if !text.isEmpty {
            Label(text, systemImage: proposal.errorCode == nil ? "brain" : "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
