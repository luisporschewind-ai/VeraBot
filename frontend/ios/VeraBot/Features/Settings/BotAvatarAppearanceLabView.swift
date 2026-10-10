import SwiftUI
import VeraBotCore

struct BotAvatarAppearanceLabView: View {
    @Binding var appearance: BotAppearance
    @Binding var size: Int
    @Binding var familyLook: BotAvatarFamilyLook
    @State private var action: BotAvatarState = .idle
    @State private var replay = 0
    @State private var compare = true
    private let previewStates: [BotAvatarState] = [.idle,.smile,.love,.starEyes,.thinking,.working]

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                preview
                shapeChoices
                if compare { comparison }
                skinChoices
                accessoryChoices
                colorChoices
                HStack {
                    Text("头部圆角")
                    Slider(value:$appearance.parameters.roundness,in:0...1).accessibilityLabel("头部圆角")
                }
                Picker("预览尺寸",selection:$size) {
                    ForEach([32,44,96,160],id:\.self) { Text(String($0)).tag($0) }
                }.pickerStyle(.segmented)
                Text("形状、皮肤和配饰会在本机记住，并与状态演示共享。实验选择暂不保存到 Bot；原色与圆角仍通过外观配置明确保存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(16)
        }.themedPageBackground().navigationTitle("家族形象与配色").navigationBarTitleDisplayMode(.inline)
    }

    private var preview: some View {
        VStack(spacing:12) {
            RobotAvatarView(action:action,size:CGFloat(size),replay:replay,appearance:appearance,familyLook:familyLook)
                .frame(maxWidth:.infinity).frame(height:210)
            Picker("预览表情",selection:$action) {
                ForEach(previewStates) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            HStack {
                Button("重播") { replay += 1 }.buttonStyle(.bordered)
                NavigationLink("全部状态演示") {
                    BotAvatarStateLabView(appearance:$appearance,size:$size,familyLook:$familyLook)
                }.buttonStyle(.bordered)
            }
            Text("拖动身体或天线 · 按住中心挤压").font(.caption).foregroundStyle(.secondary)
        }.padding(12).background(Color.sectionFill,in:RoundedRectangle(cornerRadius:20))
    }

    private var shapeChoices: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("家族形状").font(.headline)
            HStack(spacing:8) {
                ForEach(BotAvatarFamilyShape.allCases) { shape in
                    Button { familyLook.shape = shape } label: {
                        choice(title:shape.title,look:look(shape:shape),selected:familyLook.shape == shape)
                    }.buttonStyle(.plain)
                    .accessibilityLabel("形状：\(shape.title)")
                    .accessibilityAddTraits(familyLook.shape == shape ? .isSelected : [])
                }
            }
            Toggle("并排比较同色、同皮肤、同表情",isOn:$compare).font(.subheadline)
        }
    }

    private var comparison: some View {
        HStack(alignment:.bottom,spacing:6) {
            ForEach(BotAvatarFamilyShape.allCases) { shape in
                VStack(spacing:8) {
                    RobotAvatarView(action:action,size:CGFloat(min(size,72)),ambient:false,replay:replay,appearance:appearance,familyLook:look(shape:shape))
                        .allowsHitTesting(false).accessibilityHidden(true)
                    Text(shape.title).font(.caption)
                }.frame(maxWidth:.infinity)
            }
        }.padding(.vertical,20).padding(.horizontal,8)
            .background(Color.sectionFill,in:RoundedRectangle(cornerRadius:16))
    }

    private var skinChoices: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("皮肤").font(.headline)
            HStack(spacing:6) {
                Button { familyLook.skinID = nil } label: {
                    choice(title:"纯色",look:look(skinID:nil),selected:familyLook.skinID == nil)
                }.buttonStyle(.plain).accessibilityLabel("皮肤：纯色")
                ForEach(BotAvatarSkin.all) { skin in
                    Button { familyLook.skinID = skin.id } label: {
                        choice(title:skin.title,look:look(skinID:skin.id),selected:familyLook.skinID == skin.id)
                    }.buttonStyle(.plain).accessibilityLabel("皮肤：\(skin.title)")
                    .accessibilityAddTraits(familyLook.skinID == skin.id ? .isSelected : [])
                }
            }
            Text("皮肤保留参考纹路的配色。切换原色不清除皮肤，选择纯色可查看原色。").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var accessoryChoices: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("配饰").font(.headline)
            HStack(spacing:8) {
                ForEach(BotAvatarAccessory.allCases) { accessory in
                    Button { familyLook.accessory = accessory } label: {
                        choice(title:accessory.title,look:look(accessory:accessory),selected:familyLook.accessory == accessory)
                    }.buttonStyle(.plain).accessibilityLabel("配饰：\(accessory.title)")
                    .accessibilityAddTraits(familyLook.accessory == accessory ? .isSelected : [])
                }
            }
        }
    }

    private var colorChoices: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("快捷配色").font(.headline)
            HStack {
                ForEach(RobotAvatarTone.allCases) { tone in
                    let value = RobotLabColor.preset(tone).appearanceColor
                    Button { appearance.palette.body = value } label: {
                        Text(tone.title).frame(maxWidth:.infinity,minHeight:38)
                            .background(appearance.palette.body == value ? Color.brandSoft : Color.sectionFill,in:RoundedRectangle(cornerRadius:10))
                    }.buttonStyle(.plain)
                }
            }
            Text("Bot 选色卡").font(.headline)
            swatches(Array(BotAvatarColorPalette.screenshotSwatches.prefix(6)))
            swatches(Array(BotAvatarColorPalette.screenshotSwatches.suffix(5)))
        }
    }

    private func choice(title:String,look:BotAvatarFamilyLook,selected:Bool) -> some View {
        VStack(spacing:8) {
            RobotAvatarView(action:.idle,size:40,ambient:false,appearance:appearance,familyLook:look,staticPreview:true)
                .frame(height:48).allowsHitTesting(false).accessibilityHidden(true)
            Text(title).font(.caption)
        }.frame(maxWidth:.infinity,minHeight:80)
            .background(selected ? Color.brandSoft : Color.sectionFill,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(selected ? Color.primary.opacity(0.5) : .clear,lineWidth:1.5))
    }

    private func look(shape:BotAvatarFamilyShape) -> BotAvatarFamilyLook { var value=familyLook; value.shape=shape; return value }
    private func look(skinID:String?) -> BotAvatarFamilyLook { var value=familyLook; value.skinID=skinID; return value }
    private func look(accessory:BotAvatarAccessory) -> BotAvatarFamilyLook { var value=familyLook; value.accessory=accessory; return value }

    private func swatches(_ items:[BotAvatarColorOption]) -> some View {
        HStack(spacing:8) {
            ForEach(items) { swatch in
                let selected = appearance.palette.body == swatch.appearanceColor
                Button { appearance.palette.body = swatch.appearanceColor } label: {
                    Circle().fill(swatch.color).frame(width:28,height:28)
                        .overlay { if selected { Image(systemName:"checkmark").font(.system(size:12,weight:.bold)).foregroundStyle(.white) } }
                        .padding(4).overlay(Circle().stroke(selected ? Color.primary : .clear,lineWidth:2))
                        .frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("主色：\(swatch.name)").accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Shared color card used by the avatar lab and Bot creation/edit forms.
struct BotAvatarColorPicker: View {
    @Binding var selection: String
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            colorGroup("新版头像原色", options: BotAvatarColorPalette.robotTones)
            colorGroup("Bot 选色卡", options: BotAvatarColorPalette.screenshotSwatches)
        }
    }

    private func colorGroup(_ title: String, options: [BotAvatarColorOption]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(options) { option in
                    let selected = BotLook.sameColor(selection, option.hex)
                    Button { selection = option.hex } label: {
                        Circle()
                            .fill(option.appearanceColor.swiftUIColor)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(4)
                            .overlay(Circle().stroke(selected ? Color.secondary.opacity(0.65) : .clear, lineWidth: 2))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title)：\(option.name)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}
