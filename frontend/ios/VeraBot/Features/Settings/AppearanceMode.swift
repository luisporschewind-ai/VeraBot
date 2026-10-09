import SwiftUI

/// 外观：跟随系统 / 浅色 / 深色。rawValue 存入 @AppStorage(SettingsKeys.appearance)，由根视图同步到所属窗口。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    /// nil 表示不覆盖，交给系统
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
