import AVFoundation
import Foundation
import Observation
import Speech

enum SpeechInputError: LocalizedError {
    case unavailable
    case noInput

    var errorDescription: String? {
        switch self {
        case .unavailable: return "语音识别当前不可用（zh-CN）"
        case .noInput: return "未检测到麦克风输入"
        }
    }
}

/// 音频采集 + 识别引擎。刻意不隔离到 MainActor：
/// AVAudioEngine 的 tap 回调与 Speech 的结果回调都在后台线程执行，
/// 若闭包继承 MainActor 隔离，Swift 6 会在运行时触发隔离断言崩溃。
/// 内部可变状态由 NSLock 保护，因此标记为 @unchecked Sendable。
final class SpeechEngine: @unchecked Sendable {
    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var stoppedByUser = false
    // 已占用的音频资源；teardown 时各自只释放一次（幂等），避免 session / tap / engine 残留。
    private var sessionActive = false
    private var tapInstalled = false
    // 每次 start 加一；旧识别任务的迟到回调不会拆掉新一轮的音频。
    private var generation = 0

    /// 请求语音识别与麦克风权限（iOS 17+ API）。
    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(onResult: @escaping @Sendable (String, Bool) -> Void,
               onError: @escaping @Sendable (String) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else { throw SpeechInputError.unavailable }
        cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        let gen: Int = lock.withLock {
            generation += 1
            self.request = request
            self.stoppedByUser = false
            return generation
        }

        // 任何一步失败（session、无输入、engine.start）都把已占用的资源全部释放再抛出，
        // 否则 session 保持激活、tap 留在 inputNode 上，CoreAudio IO 循环会一直空转。
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            lock.withLock { sessionActive = true }

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechInputError.noInput }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.append(buffer)
            }
            lock.withLock { tapInstalled = true }
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }

        let newTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onResult(result.bestTranscription.formattedString, result.isFinal)
            }
            if error != nil || result?.isFinal == true {
                let userStopped = self?.finish(generation: gen) ?? true
                if let error, result == nil, !userStopped {
                    onError(error.localizedDescription)
                }
            }
        }
        lock.withLock {
            if generation == gen { self.task = newTask } else { newTask.cancel() }
        }
    }

    /// 用户主动结束：停止采集并等待最终结果。
    func stop() {
        lock.withLock { stoppedByUser = true }
        stopAudio()
        lock.withLock { request?.endAudio() }
    }

    /// 彻底结束（页面消失、进入后台、重新开始前）：停止采集并取消识别，不再等结果。可重复调用。
    func cancel() {
        let pending: SFSpeechRecognitionTask? = lock.withLock {
            stoppedByUser = true
            request?.endAudio()
            let t = task
            request = nil
            task = nil
            return t
        }
        stopAudio()
        pending?.cancel()
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request?.append(buffer) }
    }

    /// 释放音频资源；幂等：每样资源只在确实占用时释放一次。
    private func stopAudio() {
        let (hadTap, hadSession) = lock.withLock { () -> (Bool, Bool) in
            let r = (tapInstalled, sessionActive)
            tapInstalled = false
            sessionActive = false
            return r
        }
        if engine.isRunning {
            engine.stop()
        }
        if hadTap {
            engine.inputNode.removeTap(onBus: 0)
        }
        if hadSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// 识别结束（出错或拿到最终结果）的清理；返回是否为用户主动停止。
    /// 旧一轮的迟到回调（generation 不符）不动当前这一轮的资源。
    private func finish(generation gen: Int) -> Bool {
        let current: Bool = lock.withLock { generation == gen }
        guard current else { return true }
        stopAudio()
        return lock.withLock {
            let stopped = stoppedByUser
            request = nil
            task = nil
            return stopped
        }
    }
}

/// 供 SwiftUI 使用的语音输入状态（MainActor）。
@MainActor
@Observable
final class SpeechInput {
    var isRecording = false
    var transcript = ""
    var errorText: String?

    private let engine = SpeechEngine()

    func toggle() async {
        if isRecording {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
        errorText = nil
        guard await SpeechEngine.requestPermissions() else {
            errorText = "请在「设置」中允许 VeraBot 使用麦克风和语音识别"
            return
        }
        transcript = ""
        do {
            try engine.start(
                onResult: { [weak self] text, isFinal in
                    Task { @MainActor in
                        self?.transcript = text
                        if isFinal { self?.isRecording = false }
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.errorText = message
                        self?.isRecording = false
                    }
                })
            isRecording = true
        } catch {
            errorText = error.localizedDescription
            isRecording = false
        }
    }

    func stop() {
        engine.stop()
        isRecording = false
    }

    /// 页面消失 / 进入后台：立即释放麦克风和音频会话，不等识别结果。
    func cancel() {
        engine.cancel()
        isRecording = false
    }
}
