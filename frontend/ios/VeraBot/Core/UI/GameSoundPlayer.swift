import AVFoundation
import Foundation
import VeraBotCore

/// 游戏短音效播放器（俄罗斯方块 + 贪吃蛇共用）。
///
/// - 有限 AVAudioPlayer 池（按键 3 路、其余 2 路）+ prepareToPlay。
/// - 音频会话用 `.ambient`：遵守系统静音开关，可与其它 App 音乐混音；不启用后台音频。
/// - 与 TTS（朗读）和语音输入（录音）做小范围协调：两者优先，游戏只在它们未占用时播放。
/// - 退出页面 / 进后台 / 锁屏 / 中断 / 耳机断开时停止全部声音，不补播历史事件。
@MainActor
public final class GameSoundPlayer: @unchecked Sendable {
    public static let shared = GameSoundPlayer()

    private var pools: [GameSoundEvent: [AVAudioPlayer]] = [:]
    private var cursors: [GameSoundEvent: Int] = [:]
    private var sessionOwned = false
    private var lastKeyPressTime: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []

    private init() {
        observeAudioSessionEvents()
    }

    /// 当前开关状态（默认开启）。读取自 UserDefaults，视图的扬声器开关也写同一个 key。
    public var isEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKeys.gameSoundEnabled) == nil {
            return SettingsKeys.gameSoundEnabledDefault
        }
        return defaults.bool(forKey: SettingsKeys.gameSoundEnabled)
    }

    /// 播放一个音效事件。结果事件（吃食 / 消行 / 落地 / 结束 / 胜利）由规则层发出，输入事件由视图层发出。
    public func play(_ event: GameSoundEvent) {
        guard isEnabled else { return }
        guard !AudioSessionOwner.shared.hasHigherPriorityOwner else { return }

        if event == .keyPress {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastKeyPressTime >= 0.06 else { return }
            lastKeyPressTime = now
        }

        acquireAmbientSession()
        guard sessionOwned, let player = nextPlayer(for: event) else { return }
        player.currentTime = 0
        player.play()
    }

    /// 立即停止全部声音并让出音频会话。
    public func stopAll() {
        for (_, list) in pools {
            for player in list { player.stop() }
        }
        releaseSession()
    }

    // MARK: - Player pool

    private func nextPlayer(for event: GameSoundEvent) -> AVAudioPlayer? {
        let list = pool(for: event)
        guard !list.isEmpty else { return nil }
        let index = (cursors[event] ?? 0) % list.count
        cursors[event] = index + 1
        return list[index]
    }

    private func pool(for event: GameSoundEvent) -> [AVAudioPlayer] {
        if let existing = pools[event] { return existing }
        let count = event == .keyPress ? 3 : 2
        var created: [AVAudioPlayer] = []
        for _ in 0..<count {
            guard let url = Bundle.main.url(forResource: Self.fileName(event), withExtension: "wav", subdirectory: "Sounds"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.numberOfLoops = 0
            player.volume = Self.volume(event)
            player.prepareToPlay()
            created.append(player)
        }
        pools[event] = created
        return created
    }

    // MARK: - Audio session

    private func acquireAmbientSession() {
        guard !sessionOwned else { return }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            sessionOwned = true
        } catch {
            sessionOwned = false
        }
        #endif
    }

    private func releaseSession() {
        guard sessionOwned else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        sessionOwned = false
    }

    private func observeAudioSessionEvents() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopAll() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.stopAll() }
        })
    }

    // MARK: - Event mapping

    private static func fileName(_ event: GameSoundEvent) -> String {
        switch event {
        case .keyPress: "key_press"
        case .start: "start"
        case .pause: "pause"
        case .resume: "resume"
        case .hardDrop: "hard_drop"
        case .clearSingle: "clear_single"
        case .clearMulti: "clear_multi"
        case .eat: "eat"
        case .gameOver: "game_over"
        case .win: "win"
        }
    }

    /// 整体音量偏低；结果音略重于普通按键。
    private static func volume(_ event: GameSoundEvent) -> Float {
        switch event {
        case .keyPress, .start, .pause, .resume: 0.55
        case .clearSingle, .clearMulti, .eat, .win: 0.65
        case .hardDrop, .gameOver: 0.7
        }
    }
}
