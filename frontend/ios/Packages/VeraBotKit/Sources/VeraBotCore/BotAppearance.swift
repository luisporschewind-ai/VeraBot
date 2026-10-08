import Foundation

public enum BotAppearanceError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let reason) = self { return "外观配置无效：\(reason)" }; return nil }
}

private enum AppearanceJSON {
    static func object(_ value: JSONValue, keys: Set<String>) throws -> [String: JSONValue] {
        guard case .object(let fields) = value, Set(fields.keys) == keys else { throw BotAppearanceError.invalid("字段不完整或包含不支持的字段") }
        return fields
    }
    static func number(_ value: JSONValue?) throws -> Double {
        guard case .number(let n) = value, n.isFinite else { throw BotAppearanceError.invalid("需要有限数值") }
        return n
    }
    static func text(_ value: JSONValue?) throws -> String {
        guard case .string(let text) = value else { throw BotAppearanceError.invalid("需要文字标识") }
        return text
    }
}

public struct BotAppearanceColor: Codable, Hashable, Sendable {
    public enum Space: String, Codable, Sendable { case sRGB = "srgb", displayP3 = "display-p3" }
    public var space: Space
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(space: Space, red: Double, green: Double, blue: Double) {
        self.space = space; self.red = red; self.green = green; self.blue = blue
    }
    public init(from decoder: Decoder) throws {
        let f = try AppearanceJSON.object(JSONValue(from: decoder), keys: ["space","red","green","blue"])
        guard let gamut = Space(rawValue: try AppearanceJSON.text(f["space"])) else { throw BotAppearanceError.invalid("不支持的颜色空间") }
        self.init(space: gamut, red: try AppearanceJSON.number(f["red"]), green: try AppearanceJSON.number(f["green"]), blue: try AppearanceJSON.number(f["blue"]))
        try validate()
    }
    public func validate() throws {
        guard [red,green,blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw BotAppearanceError.invalid("颜色分量应在 0 到 1 之间") }
    }
}

public struct BotAppearance: Codable, Hashable, Sendable {
    public struct Palette: Codable, Hashable, Sendable {
        public var body: BotAppearanceColor
        public var eyes: BotAppearanceColor
        public init(body: BotAppearanceColor, eyes: BotAppearanceColor) { self.body = body; self.eyes = eyes }
        public init(from decoder: Decoder) throws {
            let f = try AppearanceJSON.object(JSONValue(from: decoder),keys:["body","eyes"])
            body = try JSONDecoder().decode(BotAppearanceColor.self,from:JSONEncoder().encode(f["body"]!))
            eyes = try JSONDecoder().decode(BotAppearanceColor.self,from:JSONEncoder().encode(f["eyes"]!))
        }
    }
    public struct Parameters: Codable, Hashable, Sendable {
        public var roundness: Double
        public init(roundness: Double) { self.roundness = roundness }
        public init(from decoder: Decoder) throws {
            let f = try AppearanceJSON.object(JSONValue(from:decoder),keys:["roundness"])
            roundness = try AppearanceJSON.number(f["roundness"])
            guard (0...1).contains(roundness) else { throw BotAppearanceError.invalid("圆角应在 0 到 1 之间") }
        }
    }
    public var schemaVersion: Int
    public var templateID: String
    public var templateVersion: Int
    public var palette: Palette
    public var parameters: Parameters
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", templateID = "template_id", templateVersion = "template_version", palette, parameters
    }
    public init(templateID: String = "cx-robot", templateVersion: Int = 1, palette: Palette, parameters: Parameters = .init(roundness:0.5), schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion; self.templateID = templateID; self.templateVersion = templateVersion
        self.palette = palette; self.parameters = parameters
    }
    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from:decoder)
        let data = try JSONEncoder().encode(raw)
        guard data.count <= 4096 else { throw BotAppearanceError.invalid("配置超过 4096 字节") }
        let f = try AppearanceJSON.object(raw,keys:["schema_version","template_id","template_version","palette","parameters"])
        let version = try AppearanceJSON.number(f["schema_version"])
        let template = try AppearanceJSON.number(f["template_version"])
        guard version == 1, template >= 1, template <= Double(Int32.max), template.rounded() == template else { throw BotAppearanceError.invalid("不支持的配置或模板版本") }
        self.init(templateID:try AppearanceJSON.text(f["template_id"]), templateVersion:Int(template),
                  palette:try JSONDecoder().decode(Palette.self,from:JSONEncoder().encode(f["palette"]!)),
                  parameters:try JSONDecoder().decode(Parameters.self,from:JSONEncoder().encode(f["parameters"]!)))
        try validate()
    }
    public func validate() throws {
        guard schemaVersion == 1, templateVersion >= 1, templateVersion <= Int32.max else { throw BotAppearanceError.invalid("不支持的配置或模板版本") }
        guard templateID.range(of:#"^[a-z][a-z0-9-]{0,63}$"#,options:.regularExpression) != nil else { throw BotAppearanceError.invalid("模板标识格式不正确") }
        try palette.body.validate(); try palette.eyes.validate()
        guard parameters.roundness.isFinite, (0...1).contains(parameters.roundness) else { throw BotAppearanceError.invalid("圆角应在 0 到 1 之间") }
        guard try JSONEncoder().encode(self).count <= 4096 else { throw BotAppearanceError.invalid("配置超过 4096 字节") }
    }
    public func jsonValue() throws -> JSONValue {
        try validate()
        return try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(self))
    }
    public static let robotDefault = BotAppearance(palette:.init(
        body:.init(space:.sRGB,red:0.031,green:0.035,blue:0.043),
        eyes:.init(space:.sRGB,red:248.0/255,green:248.0/255,blue:246.0/255)))
}
