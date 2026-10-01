import Foundation

/// 持久化设置 key（UserDefaults / @AppStorage，统一 "vb_" 前缀）。App 与 TTS 模块共用。
public enum SettingsKeys {
    public static let ttsEnabled = "vb_tts_enabled"   // 语音播放：是否在气泡上显示朗读按钮（默认开启）
    public static let ttsEngine = "vb_tts_engine"     // 语音引擎：TTSEngineKind.rawValue（默认 local）
    public static let appearance = "vb_appearance"    // 外观：system / light / dark（默认 system，跟随系统）
    public static let notificationsEnabled = "vb_notifications_enabled"   // 通知：用户开关（默认关闭，开启时申请系统授权）
    public static let hapticsEnabled = "vb_haptics_enabled"   // 触感反馈：是否播放 sensoryFeedback（默认开启）
    public static let memoryIntroShown = "vb_memory_intro_shown"   // 「Vera 了解的你」首次打开的说明是否已显示
}
