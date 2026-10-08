import Foundation

/// Explicit writes only: a failed read never replaces the original document.
public struct BotAppearanceFileStore: Sendable {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("appearance-v1.json") }
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> BotAppearance? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        guard data.count <= 4096 else { throw BotAppearanceError.invalid("配置超过 4096 字节") }
        return try JSONDecoder().decode(BotAppearance.self, from: data)
    }
    public func save(_ appearance: BotAppearance) throws {
        try appearance.validate()
        let data = try JSONEncoder().encode(appearance)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
