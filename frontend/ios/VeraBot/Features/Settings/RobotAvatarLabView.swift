import SwiftUI
import VeraBotCore

struct RobotAvatarLabView: View {
    @AppStorage("avatarLab.familyLook.v1") private var familyLookJSON = ""
    @State private var familyLook = BotAvatarFamilyLook()
    @State private var draft = BotAppearanceDraft(saved: .robotDefault)
    @State private var loaded = false
    @State private var message: String?
    @State private var size = 160
    private var appearance: Binding<BotAppearance> {
        Binding(get: { draft.current }, set: { value in
            do { try draft.update(value) } catch { message = error.localizedDescription }
        })
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                RobotAvatarView(action:.idle,size:160,appearance:draft.current,familyLook:familyLook)
                    .frame(maxWidth:.infinity).frame(height:210)
                    .background(Color.sectionFill,in:RoundedRectangle(cornerRadius:20))
                NavigationLink { BotAvatarStateLabView(appearance:appearance,size:$size,familyLook:$familyLook) } label: {
                    entry("状态演示",detail:"全部 \(BotAvatarState.allCases.count) 种 · 完整演示与循环",icon:"play.circle")
                }
                NavigationLink { BotAvatarAppearanceLabView(appearance:appearance,size:$size,familyLook:$familyLook) } label: {
                    entry("家族形象与配色",detail:"四种形状 · 原色与皮肤 · 耳机与徽章",icon:"paintpalette")
                }
                NavigationLink { BotAvatarAppearanceSaveView(draft:$draft) } label: {
                    entry("外观配置",detail:"本机保存与加载 · 指定 Bot 外观配置",icon:"square.and.arrow.down")
                }
                Text(draft.isDirty ? "当前有未保存的外观草稿" : "当前外观已载入")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Text("家族形状、皮肤和配饰仅在实验室预览，并在本机记住。正式 Bot 继续使用已保存的外观与执行状态；实验室可手动演示全部表情。")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("参考项目：Agent Robot Avatar · CX ArtLab",destination:URL(string:"https://github.com/CX-ArtLab/agent-robot-avatar")!)
                    .font(.footnote)
                Link("轮廓算法参考：Avatar Studio",destination:URL(string:"https://github.com/ai-calypse/avatar-studio")!)
                    .font(.footnote)
                Text("参考角色由 CX ArtLab 原创；许可及来源见项目说明。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
        .themedPageBackground()
        .navigationTitle("新版头像实验室").navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }; loaded = true
            if let data = familyLookJSON.data(using:.utf8), !data.isEmpty {
                do { familyLook = try JSONDecoder().decode(BotAvatarFamilyLook.self,from:data) }
                catch { message = "实验选择读取失败，原记录已保留：\(error.localizedDescription)" }
            }
            do {
                if let value = try BotAppearanceLabStore().load() {
                    guard BotAvatarTemplateRegistry.resolve(id:value.templateID,version:value.templateVersion) != nil else {
                        throw BotAppearanceError.invalid("本机配置使用了暂未安装的形象，原文件已保留")
                    }
                    draft = BotAppearanceDraft(saved:value)
                }
            } catch { message = "本机外观读取失败，原文件已保留：\(error.localizedDescription)" }
        }
        .onChange(of:familyLook) { _,value in
            if let data = try? JSONEncoder().encode(value), let text = String(data:data,encoding:.utf8) { familyLookJSON = text }
        }
    }
    private func entry(_ title:String,detail:String,icon:String) -> some View {
        HStack {
            Image(systemName:icon).font(.title2).frame(width:36)
            VStack(alignment:.leading,spacing:5) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName:"chevron.right").font(.caption)
        }.padding(16).background(Color.sectionFill,in:RoundedRectangle(cornerRadius:16))
    }
}

struct BotAvatarStateLabView: View {
    @Binding var appearance: BotAppearance
    @Binding var size: Int
    @Binding var familyLook: BotAvatarFamilyLook
    @State private var action: BotAvatarState = .idle
    @State private var ambient = true
    @State private var replay = 0
    @State private var playback = BotAvatarLabPlayback()
    @State private var demoIndex = 0
    @Environment(\.scenePhase) private var scenePhase
    private let columns = Array(repeating:GridItem(.flexible(),spacing:8),count:3)
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(spacing:12) {
                        RobotAvatarView(action:action,size:CGFloat(size),ambient:ambient,replay:replay,appearance:appearance,familyLook:familyLook)
                            .frame(maxWidth:.infinity).frame(height:190)
                        Text(action.title).font(.title3.weight(.semibold))
                        Text(action.detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if playback.running { Text("演示 \(demoIndex + 1) / \(playback.sequence.count)").font(.caption.monospacedDigit()) }
                        Text("拖动头部或天线 · 按住中心挤压 · 轻点重播").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("重播") { playback.stop(); replay += 1 }
                            Button(playback.running ? "停止" : "演示全部 \(BotAvatarState.allCases.count) 种") {
                                if playback.running { playback.stop() } else { start(.all) }
                            }
                        }.buttonStyle(.bordered)
                        HStack {
                            Button("循环当前") { start(.currentLoop) }
                            Button("状态切换测试") { start(.transitions) }
                        }.buttonStyle(.bordered)
                    }.padding(16).background(Color.sectionFill,in:RoundedRectangle(cornerRadius:20)).id("preview")
                    stateGroup("原版表情与动作",states:BotAvatarState.allCases.filter { $0.category == .original })
                    stateGroup("工作状态",states:BotAvatarState.allCases.filter { $0.category == .work })
                    Picker("预览尺寸",selection:$size) {
                        ForEach([32,44,96,160],id:\.self) { Text(String($0)).tag($0) }
                    }.pickerStyle(.segmented)
                    Toggle("自然眨眼与视线游移",isOn:$ambient)
                    Text("天线与眼睛、头部使用同一状态和时钟。系统开启减弱动态效果时保留静态表情。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(16)
            }.onChange(of:action) { _,_ in proxy.scrollTo("preview",anchor:.top) }
        }
        .themedPageBackground().navigationTitle("状态演示").navigationBarTitleDisplayMode(.inline)
        .task(id:playback.serial) { await runPlayback() }
        .onChange(of:scenePhase) { _,phase in if phase != .active { playback.stop() } }
        .onDisappear { playback.stop() }
    }
    private func start(_ mode:BotAvatarLabPlayback.Mode) { demoIndex = 0; playback.start(mode,current:action) }
    private func stateGroup(_ title:String,states:[BotAvatarState]) -> some View {
        VStack(alignment:.leading,spacing:10) {
            Text(title).font(.headline)
            LazyVGrid(columns:columns,spacing:8) {
                ForEach(states) { state in
                    Button { playback.stop(); action = state; replay += 1 } label: {
                        Text(state.title).font(.subheadline).frame(maxWidth:.infinity,minHeight:42)
                            .background(action == state ? Color.brandSoft : Color.sectionFill,in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain).accessibilityAddTraits(action == state ? .isSelected : [])
                }
            }
        }
    }
    @MainActor private func runPlayback() async {
        let serial = playback.serial
        let mode = playback.mode
        let sequence = playback.sequence
        guard playback.running else { return }
        repeat {
            for (index,next) in sequence.enumerated() {
                guard !Task.isCancelled, playback.serial == serial else { return }
                demoIndex = index
                // Continuous states already loop in the shared clock; never reset them every hold.
                if mode != .currentLoop || !next.continuous || action != next {
                    action = next; replay += 1
                }
                do { try await Task.sleep(for:.milliseconds(playback.holdMS(next))) } catch { return }
            }
        } while mode == .currentLoop && !Task.isCancelled && playback.serial == serial
        guard !Task.isCancelled,playback.serial == serial else { return }
        action = .idle; replay += 1; playback.stop()
    }
}

/// One selection owns both palette sources; choosing a swatch clears the preset highlight.
enum RobotLabColor: Equatable {
    case preset(RobotAvatarTone)
    case swatch(RobotLabSwatch)

    var appearanceColor: BotAppearanceColor {
        switch self {
        case .preset(let tone):
            let rgb: (Double,Double,Double) = switch tone {
            case .graphite: (0.031,0.035,0.043)
            case .violet: (0.19,0.13,0.29)
            case .blue: (0.10,0.19,0.28)
            }
            return .init(space:.sRGB,red:rgb.0,green:rgb.1,blue:rgb.2)
        case .swatch(let swatch): return swatch.appearanceColor
        }
    }
}

typealias RobotLabSwatch = BotAvatarColorOption
