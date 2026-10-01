import SwiftUI
import VeraBotCore

/// 首页行名称右侧的标签：一个浅灰小圆角矩形（Color.sectionFill，圆角 5），文字为「搜索, 查询, 调研」，
/// 次要灰色小字、单行、尾部截断。不显示 +N。无标签时不占位。
struct BotTagChip: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            Text(BotTagRules.display(tags))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityLabel("标签：" + tags.joined(separator: "，"))
        }
    }
}

/// 创建 / 编辑 Bot 的「标签」行：放在「基本信息」分组内，一个原生 TextField，用逗号 / 顿号 / 空格分隔。
/// 输入时即时校验（> 3 个或某个 > 4 字时下方红色 footnote 提示）；保存时由调用方用 `BotTagRules.parse(text)` 取规范化结果。
struct BotTagsField: View {
    @Binding var text: String

    var body: some View {
        LabeledContent("标签") {
            TextField("如：搜索, 查询, 调研", text: $text)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        if let error = BotTagRules.parse(text).error {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}
