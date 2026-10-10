import Foundation

/// Curated, stable silhouettes. The standard member retains the original geometry.
public enum BotAvatarFamilyShape: String, CaseIterable, Codable, Sendable, Identifiable {
    case standard, soft, tilted, rounded
    case circle, droplet, roundedTriangle, capsule, pentagon, pumpkin, roundedDroplet
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .standard: "标准"; case .soft: "微鼓"; case .tilted: "轻偏"; case .rounded: "饱满"
        case .circle: "圆形"; case .droplet: "花朵形"; case .roundedTriangle: "圆润三角形"
        case .capsule: "胶囊型"; case .pentagon: "五边形"
        case .pumpkin: "南瓜形"; case .roundedDroplet: "圆润水滴形"
        }
    }
    public var seed: UInt32? {
        switch self {
        case .standard, .circle, .droplet, .roundedTriangle, .capsule, .pentagon, .pumpkin, .roundedDroplet: nil
        case .soft: 47; case .tilted: 132; case .rounded: 70
        }
    }
}

public enum BotAvatarAccessory: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, headphones, badge
    public var id: String { rawValue }
    public var title: String {
        switch self { case .none: "无配饰"; case .headphones: "耳机"; case .badge: "小徽章" }
    }
}

public enum BotAvatarBadgeStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case spark, heart, bolt, leaf
    public var id: String { rawValue }
    public var title: String {
        switch self { case .spark: "星芒"; case .heart: "爱心"; case .bolt: "闪电"; case .leaf: "嫩叶" }
    }
}

/// Lab-only layers; deliberately separate from the persisted/server BotAppearance schema.
public struct BotAvatarFamilyLook: Codable, Equatable, Sendable {
    public var shape: BotAvatarFamilyShape
    public var skinID: String?
    public var accessory: BotAvatarAccessory
    public var badgeStyle: BotAvatarBadgeStyle
    public var skin: BotAvatarSkin? { BotAvatarSkin.all.first { $0.id == skinID } }
    public init(shape: BotAvatarFamilyShape = .standard, skinID: String? = nil, accessory: BotAvatarAccessory = .none, badgeStyle: BotAvatarBadgeStyle = .spark) {
        self.shape = shape; self.skinID = skinID; self.accessory = accessory; self.badgeStyle = badgeStyle
    }
    private enum CodingKeys: String, CodingKey { case shape, skinID, accessory, badgeStyle }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedShape = try values.decode(String.self, forKey: .shape)
        if storedShape == "roundedHeart" {
            shape = .standard
        } else if let restoredShape = BotAvatarFamilyShape(rawValue:storedShape) {
            shape = restoredShape
        } else {
            throw BotAppearanceError.invalid("实验形状暂未安装")
        }
        skinID = try values.decodeIfPresent(String.self, forKey: .skinID)
        accessory = try values.decode(BotAvatarAccessory.self, forKey: .accessory)
        badgeStyle = try values.decodeIfPresent(BotAvatarBadgeStyle.self,forKey:.badgeStyle) ?? .spark
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

    /// Explicit silhouettes used by the expanded lab family. Existing seeded members
    /// retain their established contour; new silhouettes share the same 240-unit face grid.
    public static func points(shape: BotAvatarFamilyShape, roundness: Double) -> [Point] {
        guard shape != .standard else { return [] }
        if let seed = shape.seed { return points(seed:seed,roundness:roundness) }
        let amount = roundness.isFinite ? min(1,max(0,roundness)) : 0.5
        return (0..<160).map { curatedPoint(shape:shape,index:$0,roundness:amount) }
    }

    private static func curatedPoint(shape:BotAvatarFamilyShape,index:Int,roundness:Double) -> Point {
        let angle = -Double.pi/2.0 + Double(index)*Double.pi*2.0/160.0
        let cosine = cos(angle)
        let sine = sin(angle)
        var x = 0.0
        var y = 0.0
        switch shape {
        case .circle:
            x = 96*cosine; y = 96*sine
        case .droplet:
            let narrowing = 1.0 - 0.48*pow(max(0.0,-sine),10.0)
            x = 99*cosine*narrowing; y = 89*sine*narrowing
        case .roundedTriangle:
            let base = 0.88 + 0.08*roundness
            let wave = 0.12 - 0.08*roundness
            let radius = base + wave*cos(3*(angle + .pi/2))
            x = 101*cosine*radius; y = 91*sine*radius
        case .capsule:
            let endDirection = cosine < 0 ? -1.0 : 1.0
            x = 28*endDirection + 76*cosine; y = 76*sine
        case .pentagon:
            let base = 0.94 + 0.04*roundness
            let wave = 0.06 - 0.04*roundness
            let radius = base + wave*cos(5*(angle + .pi/2))
            x = 100*cosine*radius; y = 91*sine*radius
        case .pumpkin:
            let radius = 0.92 + 0.08*cos(5*(angle + .pi/2))
            x = 101*cosine*radius; y = 90*sine*radius
        case .roundedDroplet:
            return roundedDropletPoint(index:index)
        case .standard, .soft, .tilted, .rounded:
            break
        }
        return Point(x:120+x,y:120+y)
    }

    private static func roundedDropletPoint(index:Int) -> Point {
        let segments: [(Point,Point,Point,Point)] = [
            (Point(x:120,y:37),Point(x:129,y:37),Point(x:202,y:112),Point(x:214,y:148)),
            (Point(x:214,y:148),Point(x:232,y:191),Point(x:179,y:209),Point(x:120,y:209)),
            (Point(x:120,y:209),Point(x:61,y:209),Point(x:8,y:191),Point(x:26,y:148)),
            (Point(x:26,y:148),Point(x:38,y:112),Point(x:111,y:37),Point(x:120,y:37))
        ]
        return cubicPoint(segments:segments,index:index)
    }

    private static func cubicPoint(segments:[(Point,Point,Point,Point)],index:Int) -> Point {
        let samplesPerSegment = 160/segments.count
        let segmentIndex = min(segments.count-1,index/samplesPerSegment)
        let t = Double(index%samplesPerSegment)/Double(samplesPerSegment)
        let inverse = 1-t
        let p = segments[segmentIndex]
        let x = inverse*inverse*inverse*p.0.x + 3*inverse*inverse*t*p.1.x + 3*inverse*t*t*p.2.x + t*t*t*p.3.x
        let y = inverse*inverse*inverse*p.0.y + 3*inverse*inverse*t*p.1.y + 3*inverse*t*t*p.2.y + t*t*t*p.3.y
        return Point(x:x,y:y)
    }
}
