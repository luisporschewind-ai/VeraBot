import SwiftUI
import UIKit

// MARK: - 主题（Theme）
//
// 全 App 唯一的颜色 / 样式入口：视图里只用这里的语义色（Semantic colors）与修饰符，不写死颜色值。
// 语义色由 UIColor 动态提供（随 trait 解析），设置 › 外观（跟随系统 / 浅色 / 深色）切换时所有页面一起更新。
//
//   主题「薰衣草 × 青绿」（Lavender Teal Duo，Boss 2026-10-03 选定，替换 502e11e 的纯青绿主题）
//   appBackground  页面背景      浅色 #FFFFFF；深色 #0B0B14
//   sectionFill    分组 / 卡片   浅色 #F2F2F8；深色 #1C1B2E（Bot 气泡同色）
//   brand          品牌主色      浅色 #6461D1；深色 #D7D7FF（全局 tint：导航按钮、链接、选中态、AccentColor）
//   brandFill      品牌实色底    浅色 #6461D1；深色 #4B48B8（白字的底：主按钮、默认头像）
//   brandText      品牌文字色    浅色 #2A2870；深色 #D7D7FF（登录页标题、账号名等「品牌文字」）
//   brandSoft      品牌浅底      浅色 #EEEEFF；深色 #26254A（选中态、交接 Trace 卡片）
//   userBubble     用户气泡底    浅色 #D7D7FF；深色 #3F3D9E；文字 userBubbleText 浅色 #1B1A3A / 深色 #FFFFFF
//   brandAccent    第二强调色    浅色 #3D7A8C；深色 #5FA3B6（Vera 青绿：置顶、引用竖条、用量条；= brandLight）
//   toggleTint     开关          浅色 #3D7A8C；深色 #4E9AAE
//
// 对比度（WCAG）：#6461D1 白底 5.0:1、#F2F2F8 上 4.5:1、白字在 #6461D1 上 5.0:1；深色 #D7D7FF 在 #0B0B14 上 14:1；
//   白字在 #4B48B8 上 7.2:1；用户气泡 #1B1A3A / #D7D7FF 12:1、白字 / #3F3D9E 8.9:1；#2A2870 白底 12.8:1；#3D7A8C 白底 4.8:1。
// 来源：薰衣草 #D7D7FF 与青绿 #3D7A8C 都取自 Vera CLI 主题（~/Vera/src/vera/terminal/theme.py，终端里显示的淡紫 + 青绿）。
//
// Liquid Glass：iOS 26 用系统 .glassEffect / .buttonStyle(.glass)；iOS 17–18 回退到材质 / bordered 样式。
// 底部浮动栏用 bottomBar、导航栏下方的吸顶栏用 topBar（iOS 26 safeAreaBar，带系统滚动边缘效果；旧系统 safeAreaInset）。

extension Color {
    // 主题「薰衣草 × 青绿」（Lavender Teal Duo，2026-10-03 Boss 选定方案 C）：
    // 薰衣草 #D7D7FF 家族是品牌主色（浅色模式用加深的 #6461D1 保证白字 / 文字对比度，#D7D7FF 做浅底和用户气泡；
    // 深色模式 #D7D7FF 直接做主色）；Vera 青绿 #3D7A8C 是第二强调色（开关、置顶、引用竖条、用量条）。

    /// 品牌主色（薰衣草）：全局 tint（导航按钮、链接、选中态）、强调文字与图标。浅色 #6461D1 / 深色 #D7D7FF
    static let brand = Color.dynamic(light: UIColor(hex: 0x6461D1), dark: UIColor(hex: 0xD7D7FF))
    /// 白字下面的品牌实色底（主按钮、默认头像）：浅色 #6461D1 / 深色 #4B48B8，保证白字对比度
    static let brandFill = Color.dynamic(light: UIColor(hex: 0x6461D1), dark: UIColor(hex: 0x4B48B8))
    /// 第二强调色（Vera 青绿）：引用竖条、用量进度条、置顶。浅色 #3D7A8C / 深色 #5FA3B6
    static let brandAccent = Color.dynamic(light: UIColor(hex: 0x3D7A8C), dark: UIColor(hex: 0x5FA3B6))
    /// 历史名字，等同 brandAccent
    static let brandLight = brandAccent
    /// 暗一档的青绿（Vera Light 主题 accent）
    static let brandDark = Color(hex: "#2F6F82")
    /// 品牌文字色：登录页标题、设置里的账号名。浅色 #2A2870 / 深色 #D7D7FF
    static let brandText = Color.dynamic(light: UIColor(hex: 0x2A2870), dark: UIColor(hex: 0xD7D7FF))
    /// 品牌浅底（选中态、交接 Trace 卡片）：浅色 #EEEEFF / 深色 #26254A
    static let brandSoft = Color.dynamic(light: UIColor(hex: 0xEEEEFF), dark: UIColor(hex: 0x26254A))

    /// 页面背景：浅色纯白，深色带一点紫的近黑 #0B0B14
    static let appBackground = Color.dynamic(light: UIColor(hex: 0xFFFFFF), dark: UIColor(hex: 0x0B0B14))
    /// 分组 Section / 卡片 / Bot 气泡底色：浅色 #F2F2F8，深色 #1C1B2E（都略带薰衣草色调）
    static let sectionFill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: 0x1C1B2E)
            : UIColor(hex: 0xF2F2F8)
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
    /// 置顶：左滑「置顶」按钮底色与行内置顶标记（青绿第二强调色）；「取消置顶」用系统灰
    static let pinTint = brandAccent
    static let unpinTint = Color(uiColor: .systemGray)

    /// 用户消息气泡底：浅色薰衣草 #D7D7FF / 深色 #3F3D9E
    static let userBubble = Color.dynamic(light: UIColor(hex: 0xD7D7FF), dark: UIColor(hex: 0x3F3D9E))
    /// 用户消息气泡文字：浅色深靛 #1B1A3A / 深色白
    static let userBubbleText = Color.dynamic(light: UIColor(hex: 0x1B1A3A), dark: UIColor(hex: 0xFFFFFF))
    /// 开关打开时的颜色（青绿）：浅色 #3D7A8C / 深色 #4E9AAE
    static let toggleTint = Color.dynamic(light: UIColor(hex: 0x3D7A8C), dark: UIColor(hex: 0x4E9AAE))

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

    /// 主操作按钮：iOS 26 .glassProminent（品牌实色玻璃），旧系统 .borderedProminent；底色 brandFill
    @ViewBuilder func prominentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent).tint(Color.brandFill)
        } else {
            buttonStyle(.borderedProminent).tint(Color.brandFill)
        }
    }

    /// 底部浮动栏（如对话输入栏）：iOS 26 用 `safeAreaBar(edge: .bottom)`，系统在栏后方给滚动内容加底部滚动边缘效果
    /// （Scroll edge effect，渐隐模糊，与顶部导航栏一致）；iOS 17–25 回退 `safeAreaInset(edge: .bottom)`。
    /// 两者都把内容区底部安全区让出栏高、随键盘上移，键盘避让逻辑相同。不手写渐变 / 模糊。
    @ViewBuilder func bottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, content: bar)
        } else {
            safeAreaInset(edge: .bottom, content: bar)
        }
    }

    /// 导航栏下方的吸顶栏（如提醒页「提醒／通知」分段）：iOS 26 用 `safeAreaBar(edge: .top)`，系统在栏后方给滚动内容加
    /// 顶部滚动边缘效果；iOS 17–25 回退 `safeAreaInset(edge: .top)` + 系统 `.bar` 材质底（与导航栏同材质）。
    /// 内容仍是同一个列表在滚动，大标题照常随滚动收进导航栏中间（Large title collapse）。不手写渐变 / 模糊。
    @ViewBuilder func topBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0) { bar().background(.bar) }
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
                .tint(Color.toggleTint)
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
