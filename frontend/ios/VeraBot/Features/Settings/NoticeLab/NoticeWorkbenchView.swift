import SwiftUI

struct NoticeWorkbenchView: View {
    let scenario: NoticeScenario?
    @State private var notice: BotNotice
    @State private var placement: NoticePlacement
    @State private var style = BotNoticeStyle()
    @State private var center = BotNoticeCenter()
    @State private var replay = 0
    @State private var timed = true
    @State private var duration = 3.0
    @State private var hasAction = false
    @State private var simulatedConfirmation = false

    init(scenario: NoticeScenario? = nil) {
        self.scenario = scenario
        let initial = scenario?.notice ?? BotNotice(title: "已保存", tone: .success, avatar: .success)
        _notice = State(initialValue: initial)
        _placement = State(initialValue: scenario?.proposed ?? .banner)
        _timed = State(initialValue: initial.duration != nil)
        _hasAction = State(initialValue: initial.actionTitle != nil)
    }

    private var experiment: BotNotice {
        var value = notice
        value.duration = timed ? duration : nil
        value.actionTitle = hasAction ? (notice.actionTitle ?? "重试") : nil
        return value
    }

    var body: some View {
        ThemedForm {
            Section {
                preview
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                Picker("呈现方式", selection: $placement) {
                    ForEach(NoticePlacement.allCases) { Text($0.title).tag($0) }
                }
                Text(placement.guidance).font(.footnote).foregroundStyle(.secondary)
                Button("播放顶部横幅") { center.show(experiment, key: "workbench", replacing: true) }
                    .accessibilityIdentifier("notice.play")
                Button("关闭当前提示") { center.clear() }
                if placement == .confirmation {
                    Button("比较系统确认面板") { simulatedConfirmation = true }
                }
            } header: { Text("预览") }

            Section("表达") {
                TextField("简短标题", text: $notice.title)
                TextField("补充说明（可留空）", text: $notice.detail, axis: .vertical)
                Picker("提示含义", selection: $notice.tone) {
                    ForEach(BotNoticeTone.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: notice.tone) { _, value in notice.avatar = value.avatar; replay += 1 }
                Picker("Bot 状态", selection: $notice.avatar) {
                    ForEach(BotAvatarState.allCases) { Text($0.title).tag($0) }
                }
                Button("重播 Bot 动作") { replay += 1 }
                Toggle("操作按钮", isOn: $hasAction)
                if hasAction {
                    TextField("按钮文字", text: Binding(get: { notice.actionTitle ?? "重试" }, set: { notice.actionTitle = $0 }))
                }
            }

            NoticeStyleControls(style: $style)

            Section("停留与反馈") {
                Toggle("自动关闭", isOn: $timed)
                if timed {
                    LabeledContent("停留时间", value: String(format: "%.1f 秒", duration))
                    Slider(value: $duration, in: 1...8, step: 0.5).accessibilityLabel("停留时间")
                }
                Toggle("试验减少动态效果", isOn: $style.reduceMotion)
                Toggle("试验触感反馈", isOn: $style.haptics)
                Text("同时遵循系统减少动态效果和应用触感开关。VoiceOver 开启时保留横幅，供用户阅读、操作和关闭。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if let scenario {
                Section("当前场景") {
                    LabeledContent("原有表现", value: scenario.current)
                    LabeledContent("建议位置", value: scenario.proposed.title)
                    Text("来源：\(scenario.source)").font(.caption).textSelection(.enabled)
                    Text("这里只模拟表达，不执行此场景的业务操作。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(scenario?.title ?? "自由试验").navigationBarTitleDisplayMode(.inline)
        .botNoticeHost(center, style: style) { entry in
            center.show(BotNotice(title: "已收到操作", detail: "仅模拟按钮反馈", tone: .success, avatar: .success),
                        key: entry.key, replacing: true)
        }
        .confirmationDialog("模拟确认", isPresented: $simulatedConfirmation, titleVisibility: .visible) {
            Button("模拟确认完成") {
                center.show(BotNotice(title: "已确认", tone: .success, avatar: .success), key: "confirmation", replacing: true)
            }
            Button("取消", role: .cancel) {}
        } message: { Text("这是实验，不会删除、发送或修改任何业务数据。") }
    }

    @ViewBuilder private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if placement == .empty {
                Spacer(minLength: 16)
                Text("页面暂时没有可显示的内容").font(.caption).foregroundStyle(.secondary)
            }
            if placement == .field {
                TextField("示例输入框", text: .constant(""))
                    .textFieldStyle(.roundedBorder).disabled(true)
            }
            if placement == .system {
                Text("系统通知的应用内示意").font(.caption).foregroundStyle(.secondary)
            }
            BotNoticeCard(notice: experiment, style: style, replay: replay,
                          action: hasAction ? { replay += 1 } : nil)
            if placement == .confirmation {
                Text("决定前保留明确确认，完成后再轻量反馈。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if placement == .empty { Spacer(minLength: 16) }
        }
    }
}

struct NoticeStyleControls: View {
    @Binding var style: BotNoticeStyle
    var body: some View {
        Section("样式与动画") {
            Picker("组件外观", selection: $style.appearance) {
                ForEach(BotNoticeAppearance.allCases) { Text($0.title).tag($0) }
            }
            Picker("背景", selection: $style.surface) {
                ForEach(BotNoticeSurface.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Bot 尺寸", value: "\(Int(style.botSize))")
            Slider(value: $style.botSize, in: 32...56, step: 4).accessibilityLabel("Bot 尺寸")
            LabeledContent("圆角", value: "\(Int(style.cornerRadius))")
            Slider(value: $style.cornerRadius, in: 12...28, step: 2).accessibilityLabel("圆角")
            LabeledContent("过渡时间", value: String(format: "%.2f 秒", style.motionDuration))
            Slider(value: $style.motionDuration, in: 0.2...0.6, step: 0.02).accessibilityLabel("过渡时间")
        }
    }
}
