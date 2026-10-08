import Foundation
import VeraBotCore

struct BotAppearanceLabStore {
    private let fileStore: BotAppearanceFileStore
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AvatarLab", isDirectory: true)) {
        fileStore = BotAppearanceFileStore(directory: directory)
    }
    func load() throws -> BotAppearance? { try fileStore.load() }
    func save(_ appearance: BotAppearance) throws { try fileStore.save(appearance) }
}
