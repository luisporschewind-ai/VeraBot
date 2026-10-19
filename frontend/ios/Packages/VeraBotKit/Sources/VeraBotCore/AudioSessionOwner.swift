import Foundation

/// 跨模块音频会话占用标记：语音输入（录音）与 TTS（朗读）优先级高于游戏音效。
/// 游戏音效播放器在播放前查询 `hasHigherPriorityOwner`，为真时保持静默，
/// 避免在朗读或录音期间用 `.ambient` 抢占系统音频会话。
public final class AudioSessionOwner: @unchecked Sendable {
    public static let shared = AudioSessionOwner()

    private let lock = NSLock()
    private var recording = false
    private var speaking = false

    private init() {}

    public var hasHigherPriorityOwner: Bool {
        lock.lock()
        defer { lock.unlock() }
        return recording || speaking
    }

    public func setRecording(_ active: Bool) {
        lock.lock()
        defer { lock.unlock() }
        recording = active
    }

    public func setSpeaking(_ active: Bool) {
        lock.lock()
        defer { lock.unlock() }
        speaking = active
    }
}
