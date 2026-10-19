import AVFoundation
import Foundation
import VeraBotCore
import VeraBotTTS

private final class GameVoiceCompletion: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
  let complete: @MainActor @Sendable () -> Void
  init(complete: @escaping @MainActor @Sendable () -> Void) { self.complete = complete }
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor [complete] in complete() }
  }
  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
    Task { @MainActor [complete] in complete() }
  }
}

/// At most four live voices; event data and one idle player per event are prepared
/// only while this page owns the shared game lease. No historical queue is retained.
@MainActor
public final class GameSoundPlayer {
  public static let shared = GameSoundPlayer()
  private struct Voice {
    let player: AVAudioPlayer
    let completion: GameVoiceCompletion
  }
  private var policy = GameSoundPolicy()
  private var prepared: [GameSoundEvent: AVAudioPlayer] = [:]
  private var data: [GameSoundEvent: Data] = [:]
  private var voices: [UInt64: Voice] = [:]
  private var lease: AudioLease?
  private var pageActive = false
  private var sequence: Int64 = 0
  private var observers: [NSObjectProtocol] = []
  private let coordinator = AudioSessionCoordinator.shared

  private init() { observeAudioSessionEvents() }
  public var isEnabled: Bool {
    let defaults = UserDefaults.standard
    return defaults.object(forKey: SettingsKeys.gameSoundEnabled) == nil
      ? SettingsKeys.gameSoundEnabledDefault : defaults.bool(forKey: SettingsKeys.gameSoundEnabled)
  }

  public func activate() {
    pageActive = true
    policy.setActive(true)
    // This is lifecycle synchronization, not an explicit user re-enable after route loss.
    if !isEnabled {
      execute(policy.setEnabled(false))
      return
    }
    acquireIfPossible()
  }
  public func setEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: SettingsKeys.gameSoundEnabled)
    execute(policy.setEnabled(enabled))
    if !enabled { releaseLease() } else if pageActive { acquireIfPossible() }
  }
  public func play(_ event: GameSoundEvent) {
    sequence += 1
    guard pageActive, isEnabled else { return }
    acquireIfPossible()
    guard let lease, coordinator.owns(lease) else { return }
    execute(
      policy.request(event, id: sequence, nowMs: Int(ProcessInfo.processInfo.systemUptime * 1000)))
  }
  /// Pause/background/leave: stop immediately and never automatically reactivate.
  public func stopAll() {
    pageActive = false
    execute(policy.setActive(false))
    releaseLease()
  }
  /// A deliberate pause may finish one short confirmation, then release its lease.
  public func pauseWithConfirmation() {
    stopVoices()
    policy.reset()
    play(.pause)
    pageActive = false
    if voices.isEmpty { stopAll() }
  }
  private func acquireIfPossible() {
    guard pageActive, isEnabled, policy.canPlay else { return }
    if let lease, coordinator.owns(lease) { return }
    lease = try? coordinator.acquire(
      owner: .game,
      onRevoked: { [weak self] in
        guard let self else { return }
        self.lease = nil
        self.stopVoices()
        self.policy.reset()
        self.prepared.removeAll()
      })
    guard let lease, coordinator.owns(lease) else { return }
    for event in GameSoundEvent.allCases { prepare(event) }
  }
  private func releaseLease() {
    if let lease { try? coordinator.release(lease) }
    lease = nil
    prepared.removeAll()
  }
  private func prepare(_ event: GameSoundEvent) {
    guard let lease, coordinator.owns(lease), prepared[event] == nil else { return }
    if data[event] == nil,
      let url = Bundle.main.url(
        forResource: Self.fileName(event), withExtension: "wav", subdirectory: "Sounds")
    {
      data[event] = try? Data(contentsOf: url)
    }
    guard let bytes = data[event], let player = try? AVAudioPlayer(data: bytes) else { return }
    player.numberOfLoops = 0
    player.volume = Self.volume(event)
    if player.prepareToPlay() { prepared[event] = player }
  }
  private func execute(_ commands: [GameSoundCommand]) {
    for command in commands {
      switch command {
      case .stopAll: stopVoices()
      case .stopVoice(let id):
        voices.removeValue(forKey: id)?.player.stop()
      case .play(let id, let event):
        guard let lease, coordinator.owns(lease), let player = prepared.removeValue(forKey: event)
        else {
          policy.finished(id)
          continue
        }
        let completion = GameVoiceCompletion { [weak self] in
          self?.voices.removeValue(forKey: id)
          self?.policy.finished(id)
          if let self, !self.pageActive && self.voices.isEmpty { self.stopAll() }
        }
        player.delegate = completion
        voices[id] = Voice(player: player, completion: completion)
        if !player.play() {
          voices.removeValue(forKey: id)
          policy.finished(id)
        }
        // Construct the next idle player after dispatch, not on the next press.
        prepare(event)
      }
    }
  }
  private func stopVoices() {
    for voice in voices.values { voice.player.stop() }
    voices.removeAll()
  }
  private func observeAudioSessionEvents() {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.execute(self.policy.routeDisconnected())
          self.releaseLease()
        }
      })
    observers.append(
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main)
      { [weak self] note in
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        else { return }
        Task { @MainActor in
          guard let self else { return }
          self.execute(self.policy.routeDisconnected())
          self.releaseLease()
        }
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
    case .keyPress, .start, .pause, .resume: 0.25
    case .clearSingle, .clearMulti, .eat, .win: 0.35
    case .hardDrop, .gameOver: 0.35
    }
  }
}
