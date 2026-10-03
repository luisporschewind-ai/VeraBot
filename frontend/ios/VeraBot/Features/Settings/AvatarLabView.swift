import SwiftUI
import VeraBotCore

/// 仅供设计试验的头像预览页。选择和状态只保存在本页面，不会写入 Bot 配置。
struct AvatarLabView: View {
    @State private var selectedCharacter: AvatarLabCharacterKind = .veraBean
    @State private var selectedState: AvatarLabState = .idle
    @State private var selectedSize: AvatarLabSize = .medium
    @State private var replayID = 0
    @State private var machine = ExecutionStateMachine()
    @State private var demo: Task<Void, Never>?
    @State private var demoCaption: String?

    private let stateColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                previewCard
                characterPicker
                statePicker
                sizePicker
                replayButton
                demoSection
                Text("此页面只用于比较新形象和状态表现，不会更改 Bot 的头像或资料。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .themedPageBackground()
        .navigationTitle("头像实验室")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopDemo() }
    }

    // MARK: - 按执行状态机演示一轮对话

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if demo == nil { startDemo() } else { stopDemo() }
            } label: {
                Label(demo == nil ? "按状态机演示一轮对话" : "停止演示",
                      systemImage: demo == nil ? "play.circle" : "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if let demoCaption {
                Text(demoCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func startDemo() {
        demo = Task { @MainActor in
            machine = ExecutionStateMachine()
            for step in AvatarLabDemo.script {
                guard !Task.isCancelled else { break }
                apply(step.event)
                if case .blocked = machine.state {
                    try? await Task.sleep(for: ExecutionStateMachine.blockedDisplayDuration)
                    apply(.blockedElapsed(serial: machine.blockedSerial))
                }
                try? await Task.sleep(for: .milliseconds(step.holdMS))
            }
            demo = nil
        }
    }

    private func stopDemo() {
        demo?.cancel()
        demo = nil
    }

    private func apply(_ event: ExecutionEvent) {
        machine.send(event)
        let next = AvatarLabState(machine.state)
        if next != selectedState { selectedState = next } else { replayID += 1 }
        demoCaption = "状态机：\(AvatarLabDemo.caption(machine.state)) → 头像：\(next.title)"
    }

    private var previewCard: some View {
        VStack(spacing: 12) {
            AvatarLabCharacterView(
                kind: selectedCharacter,
                state: selectedState,
                size: selectedSize.points,
                replayID: replayID
            )
            .frame(maxWidth: .infinity)
            .frame(height: 184)
            .accessibilityHidden(true)

            Text(selectedCharacter.title)
                .font(.title3.weight(.semibold))

            Text(selectedCharacter.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Label(selectedState.title, systemImage: selectedState.symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selectedCharacter.accentColor.opacity(0.13), in: Capsule())
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var characterPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("形象")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(AvatarLabCharacterKind.allCases) { kind in
                        characterOption(kind)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var statePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("状态")
            LazyVGrid(columns: stateColumns, spacing: 8) {
                ForEach(AvatarLabState.allCases) { state in
                    Button {
                        selectedState = state
                        replayID += 1
                    } label: {
                        Label(state.title, systemImage: state.symbol)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(
                                selectedState == state ? selectedCharacter.accentColor.opacity(0.14) : Color.sectionFill,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedState == state ? .isSelected : [])
                }
            }
        }
    }

    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("预览尺寸")
            Picker("预览尺寸", selection: $selectedSize) {
                ForEach(AvatarLabSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var replayButton: some View {
        Button {
            replayID += 1
        } label: {
            Label("重播状态动作", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("重新播放当前头像状态的轻微动作")
    }

    private func characterOption(_ kind: AvatarLabCharacterKind) -> some View {
        let isSelected = selectedCharacter == kind
        return Button {
            selectedCharacter = kind
        } label: {
            VStack(spacing: 6) {
                AvatarLabCharacterView(kind: kind, state: .idle, size: 46, animated: false)
                    .accessibilityHidden(true)
                Text(kind.title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 72, height: 82)
            .background(isSelected ? kind.accentColor.opacity(0.14) : Color.sectionFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum AvatarLabCharacterKind: String, CaseIterable, Identifiable {
    case veraBean
    case sprout
    case star
    case cloud
    case sugar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .veraBean: "V豆"
        case .sprout: "芽芽"
        case .star: "星点"
        case .cloud: "云朵"
        case .sugar: "方糖"
        }
    }

    var detail: String {
        switch self {
        case .veraBean: "一颗竖立、不对称的蚕豆，左侧略收、右侧饱满。"
        case .sprout: "圆润饱满的小芽团，顶上长着两片嫩叶。"
        case .star: "圆鼓鼓的软角星星，像一颗星形软糖。"
        case .cloud: "从参考图提取的云朵轮廓，保留原有比例和边缘。"
        case .sugar: "蜜桃粉软方糖，四角圆润饱满。"
        }
    }

    var bodyColor: Color {
        switch self {
        case .veraBean: Color(hex: "#FFD783")
        case .sprout: Color(hex: "#8EE3A1")
        case .star: Color(hex: "#74D3F2")
        case .cloud: Color(hex: "#C4A0F5")
        case .sugar: Color(hex: "#FF9FC5")
        }
    }

    var backdropColor: Color {
        switch self {
        case .veraBean: Color(hex: "#FFF4D9")
        case .sprout: Color(hex: "#E7FAE9")
        case .star: Color(hex: "#E5F8FD")
        case .cloud: Color(hex: "#F2EAFE")
        case .sugar: Color(hex: "#FFF0F6")
        }
    }

    var accentColor: Color {
        switch self {
        case .veraBean: Color(hex: "#E89A28")
        case .sprout: Color(hex: "#32B85E")
        case .star: Color(hex: "#159BC5")
        case .cloud: Color(hex: "#8652D2")
        case .sugar: Color(hex: "#E94F91")
        }
    }
}

enum AvatarLabState: String, CaseIterable, Identifiable {
    case idle
    case thinking
    case working
    case delegating
    case replying
    case waiting
    case done
    case blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle: "空闲"
        case .thinking: "思考中"
        case .working: "执行中"
        case .delegating: "委派中"
        case .replying: "回复中"
        case .waiting: "等你确认"
        case .done: "已完成"
        case .blocked: "遇到阻塞"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle"
        case .thinking: "ellipsis"
        case .working: "arrow.triangle.2.circlepath"
        case .delegating: "person.2"
        case .replying: "text.bubble"
        case .waiting: "hourglass"
        case .done: "checkmark"
        case .blocked: "exclamationmark"
        }
    }

    var motionDuration: Double {
        switch self {
        case .idle: 2.2
        case .thinking: 1.5
        case .working: 0.72
        case .delegating: 1.2
        case .replying: 0.6
        case .waiting: 1.8
        case .done: 1.05
        case .blocked: 1.0
        }
    }
}

private enum AvatarLabSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    var points: CGFloat {
        switch self {
        case .small: 68
        case .medium: 104
        case .large: 148
        }
    }
}

extension AvatarLabState {
    /// 持续状态：可见时循环播放；其余状态切换时播放一次。
    var isContinuous: Bool {
        switch self {
        case .thinking, .working, .delegating, .replying: true
        case .idle, .waiting, .done, .blocked: false
        }
    }

    /// 执行状态机 → 头像状态（对照表见 docs/design/EXECUTION_STATE.md §6）。
    init(_ execution: ExecutionState) {
        switch execution {
        case .idle: self = .idle
        case .recalling, .thinking: self = .thinking
        case .callingTool: self = .working
        case .delegating: self = .delegating
        case .replying: self = .replying
        case .blocked, .failed: self = .blocked
        case .awaitingConfirmation: self = .waiting
        case .completed: self = .done
        }
    }
}

/// 演示脚本：模拟后端一轮带召回、委派进度、被拒工具的 SSE 事件（字段与后端一致）。
private enum AvatarLabDemo {
    struct Step {
        let event: ExecutionEvent
        let holdMS: Int
    }

    private static func trace(_ json: String) -> ToolTrace? {
        try? JSONDecoder().decode(ToolTrace.self, from: Data(json.utf8))
    }

    static let script: [Step] = {
        var steps: [Step] = [Step(event: .sent, holdMS: 900),
                             Step(event: .status(ChatStatus(phase: "recalling", depth: 0, botName: "Vera")), holdMS: 1200)]
        if let start = trace(#"{"id":"d1","name":"ask_bot","args":{"bot_name":"小研","question":"q"}}"#),
           let done = trace(#"{"id":"d1","name":"ask_bot","args":{"bot_name":"小研"},"result":{"answer":"a"}}"#),
           let wStart = trace(#"{"id":"d2","name":"get_weather","args":{"city":"石家庄"}}"#),
           let denied = trace(#"{"id":"d2","name":"get_weather","args":{},"result":{"error":"当前 Bot 未被授权使用该能力","code":"tool_not_allowed"}}"#) {
            steps += [Step(event: .toolStart(start), holdMS: 1000),
                      Step(event: .status(ChatStatus(phase: "thinking", depth: 1, botName: "小研", parentID: "d1")), holdMS: 1400),
                      Step(event: .status(ChatStatus(phase: "tool", depth: 1, botName: "小研", tool: "get_weather", parentID: "d1")), holdMS: 1400),
                      Step(event: .toolResult(done), holdMS: 900),
                      Step(event: .toolStart(wStart), holdMS: 1000),
                      Step(event: .toolResult(denied), holdMS: 600)]
        }
        steps += [Step(event: .delta("好的，"), holdMS: 2200),
                  Step(event: .done, holdMS: 1600),
                  Step(event: .reset, holdMS: 0)]
        return steps
    }()

    static func caption(_ s: ExecutionState) -> String {
        switch s {
        case .idle: "空闲"
        case .recalling: "正在回忆"
        case .thinking: "思考中"
        case .callingTool(let name): "调用工具 \(name)"
        case .delegating(let bot, let p):
            if let p { "委派 \(bot) · \(p.botName)\(p.tool.map { " 调用 \($0)" } ?? " 思考中")" } else { "委派 \(bot)" }
        case .replying: "回复中"
        case .blocked(let code, _): "短暂受阻\(code.map { "（\($0)）" } ?? "")"
        case .awaitingConfirmation: "等你确认"
        case .completed: "已完成"
        case .failed: "出错"
        }
    }
}
