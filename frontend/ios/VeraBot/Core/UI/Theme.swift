import Foundation
import SwiftUI

/// 品牌色（Deep Teal）
extension Color {
    static let brand = Color(hex: "#0F766E")        // primary
    static let brandLight = Color(hex: "#14B8A6")   // light accent
    static let brandDark = Color(hex: "#115E59")
    static let brandSoft = Color(hex: "#E6F4F2")    // 浅底（交接 Trace 等）

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        if s.count != 6 || !Scanner(string: s).scanHexInt64(&value) {
            value = 0x0F766E
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
