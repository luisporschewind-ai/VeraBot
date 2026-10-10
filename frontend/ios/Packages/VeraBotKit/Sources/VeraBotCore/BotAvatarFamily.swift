import Foundation

/// Curated, stable silhouettes. The standard member retains the original geometry.
public enum BotAvatarFamilyShape: String, CaseIterable, Codable, Sendable, Identifiable {
    case standard, soft, tilted, rounded
    public var id: String { rawValue }
    public var title: String {
        switch self { case .standard: "标准"; case .soft: "微鼓"; case .tilted: "轻偏"; case .rounded: "饱满" }
    }
    public var seed: UInt32? {
        switch self { case .standard: nil; case .soft: 47; case .tilted: 132; case .rounded: 70 }
    }
}

public enum BotAvatarAccessory: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, headphones, badge
    public var id: String { rawValue }
    public var title: String {
        switch self { case .none: "无配饰"; case .headphones: "耳机"; case .badge: "小徽章" }
    }
}

/// Lab-only layers; deliberately separate from the persisted/server BotAppearance schema.
public struct BotAvatarFamilyLook: Codable, Equatable, Sendable {
    public var shape: BotAvatarFamilyShape
    public var skinID: String?
    public var accessory: BotAvatarAccessory
    public var skin: BotAvatarSkin? { BotAvatarSkin.all.first { $0.id == skinID } }
    public init(shape: BotAvatarFamilyShape = .standard, skinID: String? = nil, accessory: BotAvatarAccessory = .none) {
        self.shape = shape; self.skinID = skinID; self.accessory = accessory
    }
    private enum CodingKeys: String, CodingKey { case shape, skinID, accessory }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        shape = try values.decode(BotAvatarFamilyShape.self, forKey: .shape)
        skinID = try values.decodeIfPresent(String.self, forKey: .skinID)
        accessory = try values.decode(BotAvatarAccessory.self, forKey: .accessory)
        if skinID != nil && skin == nil { throw BotAppearanceError.invalid("实验皮肤暂未安装") }
    }
}

/// Swift adaptation of Avatar Studio's seeded radial-wave silhouette (MIT).
/// Copyright (c) 2026 CX ART Lab, ai-calypse. See docs/licenses/avatar-studio-MIT.txt.
public enum BotAvatarFamilySilhouette {
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
    }
    public static func points(seed: UInt32, roundness: Double) -> [Point] {
        let rounded = roundness.isFinite ? min(1, max(0, roundness)) : 0.5
        var state = seed
        func random() -> Double {
            state = state &+ 0x6d2b79f5
            var value = (state ^ (state >> 15)) &* (state | 1)
            value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
            return Double(value ^ (value >> 14)) / 4294967296
        }
        let phases = (0..<3).map { _ in random() * .pi * 2 }
        let amplitudes = [0.035 + random() * 0.015, 0.045 + random() * 0.025, 0.01 + random() * 0.01]
        let halfW = 101 + random() * 4
        let halfH = 90 + random() * 4
        let exponent = 2.2 + (1 - rounded) * 1.1
        return (0..<160).map { index in
            let angle = -.pi / 2 + Double(index) * .pi * 2 / 160
            let c = cos(angle), s = sin(angle)
            let divisor = pow(pow(abs(c) / halfW, exponent) + pow(abs(s) / halfH, exponent), 1 / exponent)
            let radius = 1 / divisor
            var wave = 1.0
            for i in 0..<3 { wave += amplitudes[i] * sin(Double(i + 2) * angle + phases[i]) }
            return Point(x:120 + c * radius * wave, y:120 + s * radius * wave)
        }
    }
}
