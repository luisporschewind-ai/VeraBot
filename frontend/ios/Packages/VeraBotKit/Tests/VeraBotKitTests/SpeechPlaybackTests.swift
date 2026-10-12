import AVFoundation
import Testing
@testable import VeraBotTTS

@MainActor private final class ControlledSynth: SpeechSynthesizing {
    weak var delegate: (any AVSpeechSynthesizerDelegate)?
    var isSpeaking = false
    var stops = 0
    var utterances: [AVSpeechUtterance] = []
    func speak(_ utterance: AVSpeechUtterance) {
        utterances.append(utterance)
        isSpeaking = true
    }
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        isSpeaking = false
        stops += 1
        return true
    }
}

@MainActor private final class ControlledSession: SpeechAudioSession {
    var active = false
    var releases = 0
    func activate() throws { active = true }
    func deactivate() throws { active = false; releases += 1 }
}

@MainActor private final class DelayedEngine: TTSEngine {
    let kind = TTSEngineKind.local
    var completions: [@MainActor () -> Void] = []
    func speak(_ text: String, onFinish: @escaping @MainActor () -> Void) {
        completions.append(onFinish)
    }
    func stop() {} // 模拟底层停止后，完成通知仍在队列中。
}

@MainActor @Test func playbackOldCompletionCannotClearSameMessageReplay() {
    let engine = DelayedEngine()
    let player = SpeechPlayer(engine: engine)
    player.toggle(id: "same", text: "第一遍")
    player.stop()
    player.toggle(id: "same", text: "第二遍")
    engine.completions[0]()
    #expect(player.isSpeaking("same"))
    engine.completions[1]()
    #expect(player.speakingID == nil)
}

@MainActor @Test func playbackSwitchIgnoresPreviousCompletion() {
    let engine = DelayedEngine()
    let player = SpeechPlayer(engine: engine)
    player.toggle(id: "a", text: "A")
    player.toggle(id: "b", text: "B")
    engine.completions[0]()
    #expect(player.isSpeaking("b"))
    player.toggle(id: "b", text: "B")
    #expect(player.speakingID == nil)
}

@MainActor @Test func playbackStopReleasesSessionExactlyOnce() {
    let synth = ControlledSynth(), session = ControlledSession()
    let engine = LocalTTSEngine(synth: synth, session: session)
    let player = SpeechPlayer(engine: engine)
    player.toggle(id: "a", text: "A")
    #expect(session.active)
    player.stop()
    player.stop()
    #expect(!session.active)
    #expect(!synth.isSpeaking)
    #expect(session.releases == 1)
    #expect(player.speakingID == nil)
}

@MainActor @Test func playbackFinishReleasesSession() async throws {
    let synth = ControlledSynth(), session = ControlledSession()
    let engine = LocalTTSEngine(synth: synth, session: session)
    let player = SpeechPlayer(engine: engine)
    player.toggle(id: "a", text: "A")
    engine.speechSynthesizer(AVSpeechSynthesizer(), didFinish: synth.utterances[0])
    try await Task.sleep(for: .milliseconds(20))
    #expect(!session.active)
    #expect(session.releases == 1)
    #expect(player.speakingID == nil)
}

@MainActor @Test func playbackOldCancellationCannotFinishNewUtterance() async throws {
    let synth = ControlledSynth(), session = ControlledSession()
    let engine = LocalTTSEngine(synth: synth, session: session)
    let player = SpeechPlayer(engine: engine)
    player.toggle(id: "a", text: "A")
    let old = synth.utterances[0]
    player.toggle(id: "b", text: "B")
    engine.speechSynthesizer(AVSpeechSynthesizer(), didCancel: old)
    engine.speechSynthesizer(AVSpeechSynthesizer(), didFinish: old)
    try await Task.sleep(for: .milliseconds(20))
    #expect(player.isSpeaking("b"))
    #expect(session.active)
    #expect(session.releases == 1)
    engine.speechSynthesizer(AVSpeechSynthesizer(), didFinish: synth.utterances[1])
    try await Task.sleep(for: .milliseconds(20))
    #expect(player.speakingID == nil)
    #expect(!session.active)
    #expect(session.releases == 2)
}

@MainActor @Test func playbackStopCancelsQueuedUtteranceBeforeSpeechBegins() {
    let synth = ControlledSynth(), session = ControlledSession()
    let engine = LocalTTSEngine(synth: synth, session: session)
    let player = SpeechPlayer(engine: engine)
    player.toggle(id: "queued", text: "尚未发声")
    synth.isSpeaking = false // 模拟刚入队，系统还未开始发声。
    player.stop()
    #expect(!session.active)
    #expect(player.speakingID == nil)
    #expect(synth.stops == 1)
}

@MainActor @Test func playbackCurrentCancellationReleasesSession() async throws {
    let synth = ControlledSynth(), session = ControlledSession()
    let engine = LocalTTSEngine(synth: synth, session: session)
    let player = SpeechPlayer(engine: engine)
    player.toggle(id: "cancelled", text: "取消")
    engine.speechSynthesizer(AVSpeechSynthesizer(), didCancel: synth.utterances[0])
    try await Task.sleep(for: .milliseconds(20))
    #expect(!session.active)
    #expect(session.releases == 1)
    #expect(player.speakingID == nil)
}

@MainActor @Test func playbackLateCancellationCannotDeactivateMicrophoneSession() async throws {
    let synth = ControlledSynth(), session = ControlledSession()
    let engine = LocalTTSEngine(synth: synth, session: session)
    let player = SpeechPlayer(engine: engine)
    player.toggle(id: "a", text: "A")
    let old = synth.utterances[0]
    player.stop()
    // 麦克风随后接管同一个系统音频会话。
    session.active = true
    engine.speechSynthesizer(AVSpeechSynthesizer(), didCancel: old)
    try await Task.sleep(for: .milliseconds(20))
    #expect(session.active)
    #expect(session.releases == 1)
    #expect(player.speakingID == nil)
}
