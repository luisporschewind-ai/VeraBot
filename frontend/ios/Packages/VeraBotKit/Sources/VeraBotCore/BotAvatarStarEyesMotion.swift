import Foundation

public enum BotAvatarStarEyesMotion {
    public struct Pose: Equatable, Sendable {
        public let morph: Double
        public let scale: Double
    }

    public static let durationMS = 2400.0

    public static func sample(milliseconds: Double, reduceMotion: Bool = false) -> Pose {
        let time = reduceMotion ? 1100 : min(durationMS, max(0, milliseconds.isFinite ? milliseconds : 0))
        let appear = quint((time - 140) / 420)
        let disappear = 1 - smooth((time - 1880) / 360)
        let morph = min(appear,disappear)
        let pulse = reduceMotion ? 1 : 1 + 0.075 * sin(max(0,time-600) / 170)
        return Pose(morph:morph,scale:pulse)
    }

    private static func smooth(_ value: Double) -> Double {
        let t = min(1,max(0,value))
        return t * t * (3 - 2 * t)
    }

    private static func quint(_ value: Double) -> Double {
        let t = min(1,max(0,value))
        return 1 - pow(1 - t,5)
    }
}
