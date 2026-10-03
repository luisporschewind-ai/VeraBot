import SwiftUI
import UIKit

// MARK: - 主题（Theme）
//
// 全 App 唯一的颜色 / 样式入口：视图里只用这里的语义色（Semantic colors）与修饰符，不写死颜色值。
// 语义色由 UIColor 动态提供（随 trait 解析），设置 › 外观（跟随系统 / 浅色 / 深色）切换时所有页面一起更新。
//
//   appBackground  页面背景      浅色 #FFFFFF；深色 #000000
//   sectionFill    分组 / 卡片   浅色 #EFEFEE（RGB 239, 239, 238）；深色 secondarySystemBackground
//   brand          品牌色        浅色 #3A7485；深色 #548EA0（全局 tint：按钮文字、导航、置顶、开关）
//   brandFill      品牌实色底    浅色 #3A7485；深色 #3D7A8C（白字的底：用户气泡、默认头像）
//   brandText      品牌文字色    浅色 #1A2B36；深色 #D7E4EE（Logo 旁的标题、账号名等「品牌文字」）
//   brandSoft      品牌浅底      浅色 #E7EEF3；深色 #1A3144（表情选中、交接 Trace 卡片）
//
// 品牌色取自 Vera CLI 主题（~/Vera/src/vera/terminal/theme.py，默认「深海」主题）：
//   accent #3D7A8C（VERA 点阵 Logo 的主体青绿）、logo #548EA0（Logo 扫光高光）、text_primary #D7E4EE（「Vera」等正文）。
//   终端 256 色下显示为 #5F8787 / #5F87AF / #D7D7FF（截图里的灰绿 + 淡紫），源头值以上面为准。
//   浅色模式把 #3D7A8C 压暗到 #3A7485：白底 5.2:1、浅灰分组 #EFEFEE 上 4.5:1；深色模式文字 / 图标用 #548EA0（黑底 5.8:1），
//   白字的实色底用 #3D7A8C（白字 4.8:1）。
//
// Liquid Glass：iOS 26 用系统 .glassEffect / .buttonStyle(.glass)；iOS 17–18 回退到材质 / bordered 样式。

extension Color {
    /// 品牌色（Vera 深海青绿，取自 Vera CLI accent / logo）：全局 tint、强调文字与图标
    static let brand = Color.dynamic(light: UIColor(hex: 0x3A7485), dark: UIColor(hex: 0x548EA0))
    /// 白字下面的品牌实色底（用户消息气泡、默认头像）：深色模式不用更亮的 #548EA0，保证白字对比度
    static let brandFill = Color.dynamic(light: UIColor(hex: 0x3A7485), dark: UIColor(hex: 0x3D7A8C))
    /// 亮一档的辅助色（引用竖条、用量进度条）：Vera logo / focus
    static let brandLight = Color.dynamic(light: UIColor(hex: 0x548EA0), dark: UIColor(hex: 0x5B9BB0))
    /// 暗一档（Vera Light 主题 accent）
    static let brandDark = Color(hex: "#2F6F82")
    /// 品牌文字色（Vera CLI text_primary #D7E4EE / Light 主题 #1A2B36）：登录页标题、设置里的账号名
    static let brandText = Color.dynamic(light: UIColor(hex: 0x1A2B36), dark: UIColor(hex: 0xD7E4EE))
    /// 品牌浅底（表情选中、交接 Trace 卡片）：Vera surface_elevated
    static let brandSoft = Color.dynamic(light: UIColor(hex: 0xE7EEF3), dark: UIColor(hex: 0x1A3144))

    /// 页面背景：浅色纯白，深色纯黑
    static let appBackground = Color.dynamic(light: .white, dark: .black)
    /// 分组 Section / 卡片 / 气泡底色：浅色 #EFEFEE（RGB 239, 239, 238），深色 secondarySystemBackground（sheet 内自动取 elevated 值）
    static let sectionFill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.secondarySystemBackground.resolvedColor(with: trait)
            : UIColor(hex: 0xEFEFEE)
    })
    /// Bot 回复气泡
    static let botBubble = sectionFill
    /// 普通工具 Trace 卡片
    static let traceFill = sectionFill
    /// 卡片里再嵌一层的内容底（如交接回答）
    static let insetFill = appBackground
    /// 消息里的代码块 / 表格底
    static let codeFill = insetFill
    /// 消息里引用块左侧竖条
    static let quoteBar = brandLight
    /// 置顶：左滑「置顶」按钮底色与行内置顶标记（品牌色）；「取消置顶」用系统灰
    static let pinTint = brand
    static let unpinTint = Color(uiColor: .systemGray)

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        if s.count != 6 || !Scanner(string: s).scanHexInt64(&value) {
            value = 0x3D7A8C
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - 页面 / 列表

/// 分组表单：白色页面背景 + 浅灰分组（替代 Form）。内容里的行可自行用 listRowBackground 覆盖。
struct ThemedForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content.listRowBackground(Color.sectionFill) }
            .themedPageBackground()
    }
}

/// 分组列表：同 ThemedForm（替代默认 insetGrouped 的 List）。
struct ThemedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List { content.listRowBackground(Color.sectionFill) }
            .themedPageBackground()
    }
}

extension View {
    /// 页面背景：隐藏系统滚动背景，铺 appBackground（浅色白 / 深色黑）
    func themedPageBackground() -> some View {
        scrollContentBackground(.hidden).background(Color.appBackground)
    }

    /// 沉浸式平铺行（首页 Bot 列表）：白底、无分隔线
    func plainListRow() -> some View {
        listRowBackground(Color.appBackground)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    /// 输入框底（登录页等）：浅灰圆角
    func themedFieldBackground() -> some View {
        padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 胶囊 / 普通玻璃按钮：iOS 26 .glass，旧系统 .bordered
    @ViewBuilder func glassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// 主操作按钮：iOS 26 .glassProminent（品牌色玻璃），旧系统 .borderedProminent
    @ViewBuilder func prominentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// 可交互玻璃底（任意形状）：iOS 26 .glassEffect(.regular.interactive())，旧系统 regularMaterial
    @ViewBuilder func glassSurface<S: Shape>(in shape: S, interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

// MARK: - 开关

/// 缩小的原生开关：仍是系统 `Toggle`（不自定义 ToggleStyle、无动画），只把开关本体缩放到 `scale`（右对齐）。
/// scaleEffect 不改变布局尺寸，行高与原生 Toggle 相同，不会裁切。全 App 的开关统一用它（设置、Bot 详情、记忆设置）。
struct CompactToggle<Label: View>: View {
    static var scale: CGFloat { 0.85 }

    @Binding var isOn: Bool
    let label: Label
    @Environment(\.isEnabled) private var isEnabled

    init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        _isOn = isOn
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .scaleEffect(Self.scale, anchor: .trailing)
        } label: {
            label.opacity(isEnabled ? 1 : 0.5)   // 禁用时与系统 Toggle 一样变淡
        }
        .accessibilityElement(children: .combine)   // VoiceOver 读作「标题 + 开关」一个元素
    }
}

extension CompactToggle where Label == Text {
    init(_ title: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }
}

/// 一组相邻的玻璃元素（如输入栏的 ＋ 与输入胶囊）：iOS 26 放进 GlassEffectContainer 统一取样与融合，旧系统直接排列。
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - 头像实验室角色色 (Avatar lab palette，浅色 / 深色)

extension Color {
    /// 五官：始终画在浅色身体上，两种模式相同。
    static let avatarInk = Color(hex: "#344047")
    static let avatarBlush = Color(hex: "#FF8293")
    /// 「遇到阻塞」角标：系统橙色（自动适配深色）。
    static let avatarBlockedMark = Color(uiColor: .systemOrange)
    /// 状态角标底色：浅色白、深色系统深灰 (secondarySystemBackground 深色值)。
    static let avatarMarkFill = Color.dynamic(light: .white, dark: UIColor(hex: 0x2C2C2E))

    static let avatarBeanBody = Color.dynamic(light: UIColor(hex: 0xFFD783), dark: UIColor(hex: 0xF2C66E))
    static let avatarBeanBackdrop = Color.dynamic(light: UIColor(hex: 0xFFF4D9), dark: UIColor(hex: 0x3D3218))
    static let avatarBeanAccent = Color.dynamic(light: UIColor(hex: 0xE89A28), dark: UIColor(hex: 0xF5B54A))

    static let avatarSproutBody = Color.dynamic(light: UIColor(hex: 0x8EE3A1), dark: UIColor(hex: 0x7ED493))
    static let avatarSproutBackdrop = Color.dynamic(light: UIColor(hex: 0xE7FAE9), dark: UIColor(hex: 0x17361F))
    static let avatarSproutAccent = Color.dynamic(light: UIColor(hex: 0x32B85E), dark: UIColor(hex: 0x5BD27F))

    static let avatarStarBody = Color.dynamic(light: UIColor(hex: 0x74D3F2), dark: UIColor(hex: 0x66C4E3))
    static let avatarStarBackdrop = Color.dynamic(light: UIColor(hex: 0xE5F8FD), dark: UIColor(hex: 0x12323D))
    static let avatarStarAccent = Color.dynamic(light: UIColor(hex: 0x159BC5), dark: UIColor(hex: 0x4CC3EA))

    static let avatarCloudBody = Color.dynamic(light: UIColor(hex: 0xC4A0F5), dark: UIColor(hex: 0xB592EA))
    static let avatarCloudBackdrop = Color.dynamic(light: UIColor(hex: 0xF2EAFE), dark: UIColor(hex: 0x2C2142))
    static let avatarCloudAccent = Color.dynamic(light: UIColor(hex: 0x8652D2), dark: UIColor(hex: 0xA57BE8))

    static let avatarSugarBody = Color.dynamic(light: UIColor(hex: 0xFF9FC5), dark: UIColor(hex: 0xF290B8))
    static let avatarSugarBackdrop = Color.dynamic(light: UIColor(hex: 0xFFF0F6), dark: UIColor(hex: 0x3D1A2A))
    static let avatarSugarAccent = Color.dynamic(light: UIColor(hex: 0xE94F91), dark: UIColor(hex: 0xF57AAE))
}
