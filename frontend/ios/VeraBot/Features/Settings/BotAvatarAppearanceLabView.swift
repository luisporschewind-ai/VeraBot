import SwiftUI
import VeraBotCore

struct BotAvatarAppearanceLabView: View {
    @Binding var appearance: BotAppearance
    @Binding var size: Int
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                RobotAvatarView(action:.idle,size:CGFloat(size),appearance:appearance)
                    .frame(maxWidth:.infinity).frame(height:210)
                    .background(Color.sectionFill,in:RoundedRectangle(cornerRadius:20))
                Text("形象模板").font(.headline)
                ForEach(BotAvatarTemplateRegistry.templates,id:\.id) { template in
                    HStack { Text(template.title); Spacer(); if appearance.templateID == template.id { Image(systemName:"checkmark") } }
                        .padding(14).background(Color.sectionFill,in:RoundedRectangle(cornerRadius:12))
                }
                Text("后续形状将复用同一套状态与动画。当前提供机器人模板。").font(.footnote).foregroundStyle(.secondary)
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
                swatches(Array(RobotLabSwatch.palette.prefix(6)))
                swatches(Array(RobotLabSwatch.palette.suffix(5)))
                HStack {
                    Text("头部圆角")
                    Slider(value:$appearance.parameters.roundness,in:0...1).accessibilityLabel("头部圆角")
                }
                Picker("预览尺寸",selection:$size) {
                    ForEach([32,44,96,160],id:\.self) { Text(String($0)).tag($0) }
                }.pickerStyle(.segmented)
                Text("当前调整作为共享草稿预览，进入外观配置后可明确保存。").font(.footnote).foregroundStyle(.secondary)
            }.padding(16)
        }.themedPageBackground().navigationTitle("形象与配色").navigationBarTitleDisplayMode(.inline)
    }
    private func swatches(_ items:[RobotLabSwatch]) -> some View {
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
