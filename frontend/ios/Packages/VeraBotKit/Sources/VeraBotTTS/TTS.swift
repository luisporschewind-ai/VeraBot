import AVFoundation
import Foundation
import Observation
import VeraBotCore

// VeraBotTTS：语音播放（Text-to-Speech, TTS）
//
// 设计：TTSEngine 协议 + 多个引擎实现（本机 / 云端），由 SpeechPlayer 统一调度。
// 新增引擎只需：1) 实现 TTSEngine；2) 在 TTSEngineKind 增加一个 case 并在 makeEngine 中返回实例。

/// 可选的语音引擎。rawValue 持久化在 UserDefaults（SettingsKeys.ttsEngine）。
public enum TTSEngineKind: String, CaseIterable, Identifiable, Sendable {
    case local   // 本机 TTS（AVSpeechSynthesizer，离线可用）
    case cloud   // 云端 TTS（即将支持）

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .local: return "本机 TTS"
        case .cloud: return "云端 TTS（即将支持）"
        }
    }

    /// 当前版本是否可用；不可用的引擎在设置页中禁用。
    public var isAvailable: Bool { self == .local }
}

@MainActor
public protocol TTSEngine: AnyObject {
    var kind: TTSEngineKind { get }
    /// 朗读文本；朗读结束（或被打断）时回调 onFinish。
    func speak(_ text: String, onFinish: @escaping @MainActor () -> Void)
    func stop()
}

/// 本机引擎：AVSpeechSynthesizer，中文语音。
@MainActor
public final class LocalTTSEngine: NSObject, TTSEngine, AVSpeechSynthesizerDelegate {
    public let kind: TTSEngineKind = .local
    private let synth = AVSpeechSynthesizer()
    private var onFinish: (@MainActor () -> Void)?

    public override init() {
        super.init()
        synth.delegate = self
    }

    public func speak(_ text: String, onFinish: @escaping @MainActor () -> Void) {
        stop()
        self.onFinish = onFinish
        #if os(iOS)  // AVAudioSession 仅 iOS；macOS 只用于 swift test
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    public func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        finish()
    }

    private func finish() {
        let cb = onFinish
        onFinish = nil
        cb?()
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
}

/// 云端引擎占位：接口已对齐，后续接入服务端 /api/tts 即可。
@MainActor
public final class CloudTTSEngine: TTSEngine {
    public let kind: TTSEngineKind = .cloud
    public func speak(_ text: String, onFinish: @escaping @MainActor () -> Void) { onFinish() }
    public func stop() {}
}

/// 全局播放器：同一时间只朗读一条消息；记录正在朗读的消息 id 供气泡按钮显示状态。
@MainActor
@Observable
public final class SpeechPlayer {
    public init() {}

    public private(set) var speakingID: String?
    private var engine: TTSEngine?

    public func isSpeaking(_ id: String) -> Bool { speakingID == id }

    public func toggle(id: String, text: String) {
        if speakingID == id { stop(); return }
        let kind = TTSEngineKind(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.ttsEngine) ?? "") ?? .local
        let engine = currentEngine(for: kind.isAvailable ? kind : .local)
        speakingID = id
        engine.speak(Self.plainText(text)) { [weak self] in
            if self?.speakingID == id { self?.speakingID = nil }
        }
    }

    public func stop() {
        engine?.stop()
        speakingID = nil
    }

    private func currentEngine(for kind: TTSEngineKind) -> TTSEngine {
        if let e = engine, e.kind == kind { return e }
        engine?.stop()
        let e = Self.makeEngine(kind)
        engine = e
        return e
    }

    public static func makeEngine(_ kind: TTSEngineKind) -> TTSEngine {
        switch kind {
        case .local: return LocalTTSEngine()
        case .cloud: return CloudTTSEngine()
        }
    }

    /// 去掉 Markdown 标记与表情前缀，避免朗读出符号。
    public static func plainText(_ s: String) -> String {
        var t = s
        for mark in ["**", "`", "#", "▍", "⚠️"] { t = t.replacingOccurrences(of: mark, with: "") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
