import Foundation

// Projection and timing adapted from CX ArtLab's wrap/love/random modules (MIT).
// Units match the upstream 240-point canvas; times are milliseconds.
enum RobotSpecialMotion {
    struct EyePose {
        var x: Double
        var y: Double = 6
        var width: Double = 54
        var height: Double = 58
        var pivot: Double = 0
        var rotation: Double = 0
    }

    private static func smooth(_ value: Double) -> Double {
        let t = max(0, min(1, value))
        return t * t * (3 - 2 * t)
    }

    static func duration(action: RobotAvatarAction) -> Double {
        action == .love ? 2880 : max(Reel(stagger: 0).end, Reel(stagger: 420).end) + 120
    }

    static func eyes(action: RobotAvatarAction, milliseconds: Double,
                     reduced: Bool, playing: Bool) -> [EyePose] {
        [-1.0, 1.0].map { side in
            switch action {
            case .waitingWrap:
                let offset = asin(34.0 / 85)
                let angle = (reduced ? 0 : wrapAngle(milliseconds)) + side * offset
                let front = cos(angle)
                let width = front > 1e-10 ? 54 / cos(offset) * front : 0
                let edge = max(0, min(1, 1 - width / 54))
                let x = 85 * sin(angle)
                return EyePose(x: x + (x < 0 ? -1 : 1) * 9 * pow(edge, 3),
                               width: width, height: 58 - 18 * smooth(edge))
            case .random:
                let reel = Reel(stagger: side < 0 ? 0 : 420)
                let position = reduced ? reel.period * 0.3 :
                    (playing ? reel.position(max(0, milliseconds - 120)) : 0)
                var offset = position.truncatingRemainder(dividingBy: reel.period)
                if offset < 0 { offset += reel.period }
                if offset > reel.period / 2 { offset -= reel.period }
                let angle = offset / 50
                let front = max(0, cos(angle))
                let edge = 1 - front
                return EyePose(x: side * 34,
                               y: 6 + 50 * sin(angle) + (angle < 0 ? -1 : 1) * 6 * pow(edge, 3),
                               width: 54 - 12.5 * smooth(edge), height: 58 * front)
            default:
                return EyePose(x: side * 34)
            }
        }
    }

    static func pulse(action: RobotAvatarAction, milliseconds: Double,
                      reduced: Bool, playing: Bool) -> Double {
        guard action == .love, playing, !reduced,
              milliseconds >= 360, milliseconds < 2520 else { return 1 }
        let phase = ((milliseconds - 360) / 760).truncatingRemainder(dividingBy: 1)
        let first = smooth(1 - abs(phase - 0.12) / 0.12)
        let second = 0.6 * smooth(1 - abs(phase - 0.36) / 0.12)
        return 1 + 0.155 * max(first, second)
    }

    private static func wrapAngle(_ milliseconds: Double) -> Double {
        let offset = asin(34.0 / 85)
        let times = [0.0, 834, 996, 1260, 1390, 2400]
        let angles = [0, -Double.pi / 2 + offset, -Double.pi / 2 - offset,
                      -3 * Double.pi / 2 + offset, -3 * Double.pi / 2 - offset, -2 * Double.pi]
        let t = milliseconds.truncatingRemainder(dividingBy: 2400)
        let index = (0..<5).first { t < times[$0 + 1] } ?? 4
        var progress = (t - times[index]) / (times[index + 1] - times[index])
        if index == 0 {
            progress = bezier(progress, 0.6123122262631361, 0, 0.8763337613684284, 0.3403039133642485)
        } else if index == 4 {
            progress = bezier(progress, 0.16771539711108435, 0.7245980352977247, 0.32366613843706765, 1)
        }
        return angles[index] + (angles[index + 1] - angles[index]) * progress
    }

    private static func bezier(_ progress: Double, _ x1: Double, _ y1: Double,
                               _ x2: Double, _ y2: Double) -> Double {
        func curve(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if curve(mid, x1, x2) < progress { low = mid } else { high = mid }
        }
        return curve((low + high) / 2, y1, y2)
    }

    private struct Reel {
        let period = Double.pi * 50
        let speed = 0.6
        let ramp = 220.0
        let distance = 40.0
        let overshoot = 8.0
        let dampedFrequency = 2 * Double.pi / 200
        let decay = 0.3 * (2 * Double.pi / 200) / sqrt(1 - 0.3 * 0.3)
        let target: Double
        let stop: Double
        let stopTime: Double
        let land: Double
        let end: Double

        init(stagger: Double) {
            let slowAt = 1000 + stagger
            let spinPosition = 0.6 * (slowAt - 220 / 2)
            var turns = max(1, ((spinPosition + 40 - 8) / (Double.pi * 50)).rounded())
            while turns * Double.pi * 50 + 8 - 40 < 0.6 * 220 / 2 { turns += 1 }
            target = turns * Double.pi * 50
            stop = target + 8 - 40
            stopTime = stop / 0.6 + 220 / 2
            land = stopTime + 2 * 40 / 0.6
            end = land + log(8 / 0.1) / (0.3 * (2 * Double.pi / 200) / sqrt(1 - 0.3 * 0.3))
        }

        func position(_ t: Double) -> Double {
            if t < stopTime {
                return t < ramp ? speed * t * t / (2 * ramp) : speed * (t - ramp / 2)
            }
            if t < land {
                let u = (t - stopTime) / (land - stopTime)
                let h10 = u * u * u - 2 * u * u + u
                let h01 = -2 * u * u * u + 3 * u * u
                return stop + distance * (2 * h10 + h01)
            }
            if t >= end { return target }
            let tau = t - land
            return target + overshoot * exp(-decay * tau) *
                (cos(dampedFrequency * tau) + decay / dampedFrequency * sin(dampedFrequency * tau))
        }
    }
}
