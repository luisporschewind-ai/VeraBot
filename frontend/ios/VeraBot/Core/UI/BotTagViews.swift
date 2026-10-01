import SwiftUI
import VeraBotCore

/// 名称右侧的紧凑标签：次要文字小胶囊。放不下的用「+N」，单个过长则尾部截断。
struct BotTagChips: View {
    let tags: [String]
    var maxVisible: Int = 2
    var chipMaxWidth: CGFloat = 72

    var body: some View {
        let visible = Array(tags.prefix(max(maxVisible, 0)))
        let extra = tags.count - visible.count
        if !visible.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, tag in
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .frame(maxWidth: chipMaxWidth)
                        .background(.quaternary, in: Capsule())
                }
                if extra > 0 {
                    Text("+\(extra)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("标签：" + tags.joined(separator: "，"))
        }
    }
}

/// 创建 / 编辑 Bot 的标签分组：系统 Form 行，添加、修改、左滑删除。无自定义动画。
struct BotTagsSection: View {
    @Binding var tags: [String]
    @State private var draft = ""
    @State private var message: String?

    var body: some View {
        Section {
            ForEach(tags.indices, id: \.self) { index in
                TextField("标签", text: binding(at: index))
            }
            .onDelete { offsets in
                tags.remove(atOffsets: offsets)
                message = nil
            }
            HStack {
                TextField("添加标签", text: $draft)
                    .onSubmit(add)
                Button("添加", action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("标签")
        } footer: {
            Text("最多 5 个，每个最多 12 个字。点按可修改，左滑删除。")
        }
    }

    private func binding(at index: Int) -> Binding<String> {
        Binding(get: { tags[index] }, set: { tags[index] = $0 })
    }

    private func add() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = ""
            return
        }
        let cleaned = BotTagRules.normalized(tags + [trimmed])
        if let reason = cleaned.error {
            message = reason
            return
        }
        if cleaned.tags == BotTagRules.normalized(tags).tags {
            message = "已有相同标签"
        } else {
            tags = cleaned.tags
            draft = ""
            message = nil
        }
    }
}
