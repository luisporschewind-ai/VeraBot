import SwiftUI
import VeraBotCore

/// 👍 / 👎 消息反馈（记忆 M2 风格校准，docs/design/MEMORY_GROWTH.md §11.1）：与 🔊 同一行，只出现在
/// 已落库、不在生成中且有正文的 Bot 回复下。再点一次已选中的按钮 = 撤销评价；👎 先选理由。
struct FeedbackButtons: View {
    let item: ChatViewModel.Item
    let vm: ChatViewModel

    @State private var askingReason = false

    private var rating: Int? { item.feedback?.rating }
    private var busy: Bool { vm.feedbackBusy.contains(item.id) }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if rating == 1 {
                    Task { await vm.clearFeedback(item) }
                } else {
                    Task { await vm.setFeedback(item, rating: 1, reason: nil) }
                }
            } label: {
                icon("hand.thumbsup", selected: rating == 1)
            }
            .accessibilityLabel(rating == 1 ? "取消「有帮助」" : "这条回答有帮助")

            Button {
                if rating == -1 {
                    Task { await vm.clearFeedback(item) }   // 已 👎：再点一次撤销，不再问理由
                } else {
                    askingReason = true
                }
            } label: {
                icon("hand.thumbsdown", selected: rating == -1)
            }
            .accessibilityLabel(rating == -1 ? "取消「没帮助」" : "这条回答没帮助")
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .confirmationDialog("哪里不满意？", isPresented: $askingReason, titleVisibility: .visible) {
            ForEach(FeedbackReason.allCases) { reason in
                Button(reason.title) { Task { await vm.setFeedback(item, rating: -1, reason: reason) } }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func icon(_ name: String, selected: Bool) -> some View {
        Image(systemName: selected ? "\(name).fill" : name)
            .font(.footnote)
            .foregroundStyle(selected ? Color.brand : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
    }
}
