import SwiftUI

struct NoticeInteractionLabView: View {
    @State private var center = BotNoticeCenter()
    @State private var style = BotNoticeStyle()
    @State private var sequence: Sequence?
    @State private var presentation: Presentation?
    @State private var input = ""
    @Environment(\.scenePhase) private var scenePhase

    private enum Sequence: String { case retry, work }
    private enum Presentation: String, Identifiable {
        case sheet, cover
        var id: String { rawValue }
    }

    var body: some View {
        ThemedForm {
            Section {
                Text("这里只播放本机示例，不发请求、不操作剪贴板、不改业务数据。")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("待显示", value: "\(center.pendingCount)")
                Button("连续三条提示") {
                    sequence = nil; center.clear()
                    center.show(sample("已复制"), key: "copy")
                    center.show(sample("设置已保存"), key: "save")
                    center.show(sample("Bot 已置顶"), key: "pin")
                }
                Button("同一提示连续触发五次") {
                    sequence = nil; center.clear()
                    for _ in 0..<5 { center.show(sample("已复制"), key: "copy") }
                }
                Button("处理中 → 失败 → 重试 → 完成") { start(.retry) }
                Button("回忆 → 思考 → 执行 → 委派 → 回复 → 完成") { start(.work) }
                Button("停止演示并清空") { sequence = nil; center.clear() }
            } header: { Text("连续状态") }
              footer: { Text("同一条重复提示合并；同一任务原位更新。最多保留五条待显示提示，超出时保留较新的内容。") }

            Section("不同页面") {
                TextField("输入一些文字，试验键盘打开时的提示", text: $input)
                    .accessibilityIdentifier("notice.keyboardInput")
                Button("键盘上方播放顶部提示") { center.show(sample("输入内容已保留"), key: "keyboard", replacing: true) }
                Button("在弹出页面中试验") { sequence = nil; center.clear(); presentation = .sheet }
                    .accessibilityIdentifier("notice.sheet")
                Button("在全屏页面中试验") { sequence = nil; center.clear(); presentation = .cover }
                    .accessibilityIdentifier("notice.cover")
                Button("长文案与按钮") {
                    center.show(BotNotice(title: "当前设置已保存，头像暂时未能更新",
                                          detail: "这是一条较长的说明，用来检查小屏幕、大字体和换行后的阅读与操作。",
                                          tone: .warning, avatar: .warning, actionTitle: "重试", duration: nil),
                                key: "long", replacing: true)
                }
            }
            NoticeStyleControls(style: $style)
            Section("验收要点") {
                Text("上滑关闭、自动关闭、重试按钮、返回页面后的清理，以及浅色 / 深色 / 原生风格。大字体与 VoiceOver 使用系统设置试验。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("交互与连续状态").navigationBarTitleDisplayMode(.inline)
        .botNoticeHost(center, style: style) { entry in
            center.show(sample("重试已完成"), key: entry.key, replacing: true)
        }
        .sheet(item: presentationBinding(.sheet)) { _ in
            NoticePresentationProbe(style: style, fullScreen: false)
        }
        .fullScreenCover(item: presentationBinding(.cover)) { _ in
            NoticePresentationProbe(style: style, fullScreen: true)
        }
        .task(id: sequence) {
            guard let sequence else { return }
            await run(sequence)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { sequence = nil } }
        .onDisappear { sequence = nil }
    }

    private func presentationBinding(_ kind: Presentation) -> Binding<Presentation?> {
        Binding(get: { presentation == kind ? presentation : nil }, set: { value in
            if value != nil || presentation == kind { presentation = value }
        })
    }

    private func sample(_ title: String) -> BotNotice {
        BotNotice(title: title, tone: .success, avatar: .success, duration: 2)
    }

    private func start(_ value: Sequence) {
        // A second tap stops the same sequence; a later tap starts it afresh.
        center.clear(); sequence = sequence == value ? nil : value
    }

    private func run(_ sequence: Sequence) async {
        let frames: [BotNotice] = sequence == .retry ? [
            BotNotice(title: "正在保存…", tone: .progress, avatar: .working, duration: nil),
            BotNotice(title: "暂时未能保存", tone: .failure, avatar: .failure, duration: nil),
            BotNotice(title: "正在重试…", tone: .progress, avatar: .waiting, duration: nil),
            sample("已保存")
        ] : [
            BotNotice(title: "正在回想…", tone: .progress, avatar: .recalling, duration: nil),
            BotNotice(title: "正在想一想…", tone: .progress, avatar: .thinking, duration: nil),
            BotNotice(title: "正在处理…", tone: .progress, avatar: .working, duration: nil),
            BotNotice(title: "正在请伙伴协助…", tone: .progress, avatar: .delegating, duration: nil),
            BotNotice(title: "正在回复…", tone: .progress, avatar: .replying, duration: nil),
            sample("处理完成")
        ]
        for frame in frames {
            guard !Task.isCancelled else { return }
            center.show(frame, key: "sequence", replacing: true)
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }
}

private struct NoticePresentationProbe: View {
    let style: BotNoticeStyle
    let fullScreen: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var center = BotNoticeCenter()

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    Text("提示属于当前弹出页面。关闭页面后，其显示与计时一并结束。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("播放提示") {
                        center.show(BotNotice(title: "当前页面已保存", tone: .success, avatar: .success, duration: nil),
                                    key: "presentation", replacing: true)
                    }.accessibilityIdentifier("notice.modalPlay")
                    Button("带操作的提示") {
                        center.show(BotNotice(title: "暂时未能保存", tone: .failure, avatar: .failure,
                                              actionTitle: "重试", duration: nil), key: "presentation", replacing: true)
                    }
                }
            }
            .navigationTitle(fullScreen ? "全屏提示试验" : "弹出页面提示试验")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissToolbarButton(kind: .close) { dismiss() }
                        .accessibilityIdentifier("notice.modalClose")
                }
            }
            .botNoticeHost(center, style: style) { entry in
                center.show(BotNotice(title: "重试完成", tone: .success, avatar: .success), key: entry.key)
            }
        }
    }
}
