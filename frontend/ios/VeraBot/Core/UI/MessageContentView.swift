import SwiftUI
import UIKit
import VeraBotCore

/// Bot 回复的富文本排版（MarkdownRenderer）：解析交给 VeraBotCore.MessageMarkdown（有单元测试），这里只负责把块排成原生 SwiftUI 视图。
/// 支持 标题 / 段落 / 有序·无序列表（含缩进）/ 引用 / 代码块 / 表格 / 分隔线；行内 粗体 / 斜体 / 行内代码 / 链接，
/// 自动识别网址、电话、邮箱。链接点按走环境里的 openURL（对话页用 .inAppBrowser() 接管 http/https）。
struct MessageContentView: View {
    let text: String

    var body: some View {
        let blocks = MessageMarkdown.blocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MessageBlockView(block: block)
            }
        }
    }
}

private struct MessageBlockView: View {
    let block: MessageBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MessageMarkdown.inline(text))
                .font(level == 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(MessageMarkdown.inline(text))
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker(item)).monospacedDigit().foregroundStyle(.secondary)
                        Text(MessageMarkdown.inline(item.text))
                    }
                    .padding(.leading, CGFloat(item.level) * 16)
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.quoteBar).frame(width: 3)
                Text(MessageMarkdown.inline(text)).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let language {
                    Text(language).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code).font(.system(.footnote, design: .monospaced))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.codeFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .table(let header, let rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                            Text(MessageMarkdown.inline(cell)).font(.subheadline.bold())
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(MessageMarkdown.inline(cell)).font(.subheadline)
                            }
                        }
                    }
                }
                .padding(10)
            }
            .background(Color.codeFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .rule:
            Divider()
        }
    }

    private func marker(_ item: MessageListItem) -> String {
        if let n = item.number { return "\(n)." }
        return ["•", "◦", "▪"][min(item.level, 2)]
    }
}

/// 气泡长按菜单：复制全文 + 每个链接「复制链接」（网址 / 电话 / 邮箱，复制时去掉 tel: / mailto: 前缀）
struct MessageCopyMenu: View {
    let text: String

    var body: some View {
        Button { UIPasteboard.general.string = text } label: { Label("复制", systemImage: "doc.on.doc") }
        ForEach(MessageMarkdown.links(in: text), id: \.self) { url in
            Button { UIPasteboard.general.string = Self.copyText(url) } label: {
                Label("复制链接 \(Self.copyText(url))", systemImage: icon(url))
            }
        }
    }

    static func copyText(_ url: URL) -> String {
        switch url.scheme?.lowercased() {
        case "tel", "mailto": String(url.absoluteString.drop(while: { $0 != ":" }).dropFirst())
        default: url.absoluteString
        }
    }

    private func icon(_ url: URL) -> String {
        switch url.scheme?.lowercased() {
        case "tel": "phone"
        case "mailto": "envelope"
        default: "link"
        }
    }
}
