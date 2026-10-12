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
protocol SpeechSynthesizing: AnyObject {
    var delegate: (any AVSpeechSynthesizerDelegate)? { get set }
    var isSpeaking: Bool { get }
    func speak(_ utterance: AVSpeechUtterance)
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechSynthesizing {}

@MainActor
protocol SpeechAudioSession {
    func activate() throws
    func deactivate() throws
}

struct SystemSpeechAudioSession: SpeechAudioSession {
    func activate() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
        #endif
    }

    func deactivate() throws {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

// 只跨线程保留对象身份，不读写 AVSpeechUtterance 的可变属性。
// 保留引用也避免旧对象释放后，地址被新 utterance 重用。
private struct UtteranceIdentity: @unchecked Sendable {
    let value: AVSpeechUtterance
}

@MainActor
public final class LocalTTSEngine: NSObject, TTSEngine, AVSpeechSynthesizerDelegate {
    public let kind: TTSEngineKind = .local
    private let synth: any SpeechSynthesizing
    private let session: any SpeechAudioSession
    private var onFinish: (@MainActor () -> Void)?
    private var utterance: AVSpeechUtterance?
    private var sessionActive = false

    public override init() {
        synth = AVSpeechSynthesizer()
        session = SystemSpeechAudioSession()
        super.init()
        synth.delegate = self
    }

    init(synth: any SpeechSynthesizing, session: any SpeechAudioSession) {
        self.synth = synth
        self.session = session
        super.init()
        synth.delegate = self
    }

    public func speak(_ text: String, onFinish: @escaping @MainActor () -> Void) {
        stop()
        self.onFinish = onFinish
        do {
            try session.activate()
            sessionActive = true
        } catch {
            finish()
            return
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance = u
        synth.speak(u)
    }

    public func stop() {
        // 包括已经入队、尚未开始发声的 utterance。
        if utterance != nil || synth.isSpeaking { _ = synth.stopSpeaking(at: .immediate) }
        finish()
    }

    private func finish(for completed: AVSpeechUtterance? = nil) {
        // A 的 didCancel / didFinish 可能在 B 启动后才到达。
        if let completed, completed !== utterance { return }
        utterance = nil
        let cb = onFinish
        onFinish = nil
        if sessionActive {
            do {
                try session.deactivate()
                sessionActive = false
            } catch { /* 保留占用标记，下次 stop 时重试释放。 */ }
        }
        cb?()
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = UtteranceIdentity(value: utterance)
        Task { @MainActor in self.finish(for: identity.value) }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identity = UtteranceIdentity(value: utterance)
        Task { @MainActor in self.finish(for: identity.value) }
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

    init(engine: any TTSEngine) { self.engine = engine }

    public private(set) var speakingID: String?
    private var engine: TTSEngine?
    private var generation: UInt64 = 0

    public func isSpeaking(_ id: String) -> Bool { speakingID == id }

    public func toggle(id: String, text: String) {
        if speakingID == id { stop(); return }
        stop()
        let kind = TTSEngineKind(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.ttsEngine) ?? "") ?? .local
        let engine = currentEngine(for: kind.isAvailable ? kind : .local)
        let generation = generation
        speakingID = id
        engine.speak(Self.plainText(text)) { [weak self] in
            if self?.generation == generation { self?.speakingID = nil }
        }
    }

    public func stop() {
        generation &+= 1
        speakingID = nil
        engine?.stop()
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
