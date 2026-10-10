import Foundation

/// Smile envelope shared by all avatar templates. Reduced motion retains the expression.
public enum BotAvatarSmileMotion {
    public static let durationMS = 2600.0

    public static func sample(milliseconds: Double, reduceMotion: Bool = false) -> Double {
        if reduceMotion { return 1 }
        let time = min(durationMS, max(0, milliseconds.isFinite ? milliseconds : 0))
        return min(smooth((time - 140) / 380), 1 - smooth((time - 2060) / 420))
    }

    private static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}
