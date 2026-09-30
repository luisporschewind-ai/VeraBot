import Foundation

/// 持久化设置 key（UserDefaults / @AppStorage，统一 "vb_" 前缀）。App 与 TTS 模块共用。
public enum SettingsKeys {
    public static let ttsEnabled = "vb_tts_enabled"   // 语音播放：是否在气泡上显示朗读按钮（默认开启）
    public static let ttsEngine = "vb_tts_engine"     // 语音引擎：TTSEngineKind.rawValue（默认 local）
}
