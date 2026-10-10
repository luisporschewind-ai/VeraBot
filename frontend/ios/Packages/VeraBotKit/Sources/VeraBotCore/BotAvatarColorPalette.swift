import Foundation

/// A selectable robot body color stored through the existing Bot `color` field.
public struct BotAvatarColorOption: Equatable, Identifiable, Sendable {
    public let name: String
    public let hex: String
    public let appearanceColor: BotAppearanceColor
    public var id: String { hex }

    public var rgb: UInt32 {
        UInt32(hex.dropFirst().suffix(6), radix: 16) ?? 0
    }

    fileprivate init(name: String, hex: String, space: BotAppearanceColor.Space = .sRGB) {
        self.name = name
        self.hex = hex.uppercased()
        let value = UInt32(hex.dropFirst().suffix(6), radix: 16) ?? 0
        appearanceColor = BotAppearanceColor(
            space: space,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

public enum BotAvatarColorPalette {
    /// The three colors already offered by the new avatar lab.
    public static let robotTones = [
        BotAvatarColorOption(name: "石墨", hex: "#08090B"),
        BotAvatarColorOption(name: "深紫", hex: "#30214A"),
        BotAvatarColorOption(name: "深蓝", hex: "#1A3047")
    ]

    /// The colors from the VeraBot color card screenshot, retained in Display P3.
    public static let screenshotSwatches = [
        BotAvatarColorOption(name: "黑色", hex: "#000000", space: .displayP3),
        BotAvatarColorOption(name: "棕色", hex: "#8C6640", space: .displayP3),
        BotAvatarColorOption(name: "红色", hex: "#EA4045", space: .displayP3),
        BotAvatarColorOption(name: "橙色", hex: "#EC702E", space: .displayP3),
        BotAvatarColorOption(name: "琥珀", hex: "#F09D38", space: .displayP3),
        BotAvatarColorOption(name: "绿色", hex: "#5AC67A", space: .displayP3),
        BotAvatarColorOption(name: "青绿", hex: "#54B9A6", space: .displayP3),
        BotAvatarColorOption(name: "蓝色", hex: "#3C82F5", space: .displayP3),
        BotAvatarColorOption(name: "紫色", hex: "#895BF5", space: .displayP3),
        BotAvatarColorOption(name: "粉色", hex: "#EA4698", space: .displayP3),
        BotAvatarColorOption(name: "灰色", hex: "#777777", space: .displayP3)
    ]

    public static let all = robotTones + screenshotSwatches
    public static let defaultColor = robotTones[0].hex

    public static func option(for hex: String) -> BotAvatarColorOption? {
        all.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }

    /// Resolves known Display P3 swatches faithfully and accepts any existing six-digit hex color.
    public static func appearanceColor(for hex: String) -> BotAppearanceColor? {
        if let option = option(for: hex) { return option.appearanceColor }
        guard hex.first == "#", hex.count == 7,
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return BotAppearanceColor(space: .sRGB,
                                  red: Double((value >> 16) & 0xFF) / 255,
                                  green: Double((value >> 8) & 0xFF) / 255,
                                  blue: Double(value & 0xFF) / 255)
    }
}
