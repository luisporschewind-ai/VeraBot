import SwiftUI

/// 独立复刻实验；选择仅留在本页，不连接 Bot 资料或对话状态。
struct RobotAvatarLabView: View {
    @State private var action: RobotAvatarAction = .idle
    @State private var size = 160
    @State private var roundness = 0.5
    @State private var colorSelection: RobotLabColor = .preset(.graphite)
    @State private var ambient = true
    @State private var replay = 0
    @State private var demoRunning = false
    @State private var demoIndex = 0
    @Environment(\.scenePhase) private var scenePhase

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview.id("preview")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("表情与动作").font(.headline)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(RobotAvatarAction.allCases) { item in
                                Button {
                                    demoRunning = false
                                    action = item
                                    replay += 1
                                } label: {
                                    Text(item.title)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(action == item ? Color.brandSoft : Color.sectionFill,
                                                    in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(action == item ? .isSelected : [])
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("外观").font(.headline)
                        Picker("预览尺寸", selection: $size) {
                            Text("32").tag(32)
                            Text("44").tag(44)
                            Text("96").tag(96)
                            Text("160").tag(160)
                        }
                        .pickerStyle(.segmented)
                        colorPicker
                        HStack {
                            Text("头部圆角")
                            Slider(value: $roundness, in: 0...1)
                                .accessibilityLabel("头部圆角")
                        }
                        Toggle("自然眨眼与视线游移", isOn: $ambient)
                    }
                    Text("新版仅用于复刻预览，不会替换现有 Bot 头像。小尺寸检查辨识度，大尺寸体验表情和拖动回弹。系统开启「减弱动态效果」时保留静态表情。")
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("参考项目").font(.subheadline.weight(.semibold))
                        Link("Agent Robot Avatar · CX ArtLab",
                             destination: URL(string: "https://github.com/CX-ArtLab/agent-robot-avatar")!)
                        Text("SwiftUI 复刻实验。参考角色由 CX ArtLab 原创；许可及来源见项目说明。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .onChange(of: action) { _, _ in
                proxy.scrollTo("preview", anchor: .top)
            }
        }
        .themedPageBackground()
        .navigationTitle("新版头像实验室")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: demoRunning) {
            guard demoRunning else { return }
            for (index, next) in RobotAvatarAction.allCases.enumerated() {
                guard !Task.isCancelled else { return }
                demoIndex = index
                action = next
                replay += 1
                do { try await Task.sleep(for: .milliseconds(RobotAvatarMotion.demoDuration(next))) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            action = .idle
            replay += 1
            demoRunning = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { demoRunning = false }
        }
        .onDisappear { demoRunning = false }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(RobotAvatarTone.allCases) { tone in
                    let selected = colorSelection == .preset(tone)
                    Button { colorSelection = .preset(tone) } label: {
                        Text(tone.title)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(selected ? Color.brandSoft : Color.sectionFill,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("Bot 选色卡").font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                swatchRow(Array(RobotLabSwatch.palette.prefix(6)))
                swatchRow(Array(RobotLabSwatch.palette.suffix(5)))
            }
        }
    }

    private func swatchRow(_ swatches: [RobotLabSwatch]) -> some View {
        HStack(spacing: 8) {
            ForEach(swatches) { swatch in
                let selected = colorSelection == .swatch(swatch)
                Button { colorSelection = .swatch(swatch) } label: {
                    Circle().fill(swatch.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(4)
                        .overlay(Circle().stroke(selected ? Color.primary : Color.clear, lineWidth: 2))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("主色：\(swatch.name)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 12) {
            RobotAvatarView(action: action, size: CGFloat(size), roundness: roundness,
                            color: colorSelection.color, ambient: ambient, replay: replay)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
            Text(action.title).font(.title3.weight(.semibold))
            Text(action.detail)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if demoRunning {
                Text("演示 \(demoIndex + 1) / \(RobotAvatarAction.allCases.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text("拖动头部或天线 · 按住中心挤压 · 轻点重播")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    demoRunning = false
                    replay += 1
                } label: {
                    Label("重播", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("重播当前动作")
                Button {
                    if !demoRunning { demoIndex = 0 }
                    demoRunning.toggle()
                } label: {
                    Label(demoRunning ? "停止" : "演示全部",
                          systemImage: demoRunning ? "stop.circle" : "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(demoRunning ? "停止演示" : "演示全部 \(RobotAvatarAction.allCases.count) 种状态")
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// One selection owns both palette sources; choosing a swatch clears the preset highlight.
private enum RobotLabColor: Equatable {
    case preset(RobotAvatarTone)
    case swatch(RobotLabSwatch)

    var color: Color {
        switch self {
        case .preset(let tone): tone.color
        case .swatch(let swatch): swatch.color
        }
    }
}

/// Flat center pixels sampled from the user's Display P3 screenshot (2026-10-07 23:31:35).
/// Keep the source gamut instead of interpreting the encoded components as sRGB.
private struct RobotLabSwatch: Equatable, Identifiable {
    let name: String
    let rgb: UInt32
    var id: UInt32 { rgb }
    var color: Color {
        Color(.displayP3,
              red: Double((rgb >> 16) & 0xFF) / 255,
              green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255)
    }
    static let palette: [RobotLabSwatch] = [
        .init(name: "黑色", rgb: 0x000000),
        .init(name: "棕色", rgb: 0x8C6640),
        .init(name: "红色", rgb: 0xEA4045),
        .init(name: "橙色", rgb: 0xEC702E),
        .init(name: "琥珀", rgb: 0xF09D38),
        .init(name: "绿色", rgb: 0x5AC67A),
        .init(name: "青绿", rgb: 0x54B9A6),
        .init(name: "蓝色", rgb: 0x3C82F5),
        .init(name: "紫色", rgb: 0x895BF5),
        .init(name: "粉色", rgb: 0xEA4698),
        .init(name: "灰色", rgb: 0x777777),
    ]
}

#Preview {
    NavigationStack { RobotAvatarLabView() }
}
