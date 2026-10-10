import Foundation
import VeraBotCore

// Agent Robot Avatar 0.5.2 (MIT): port of core/actions/waiting/inspect timing and geometry.
// Time is measured from the user's action in milliseconds, including preparation pauses.
enum RobotAvatarMotion {
    struct Eye {
        var x: Double
        var y = 6.0
        var width = 54.0
        var height = 58.0
        var top = -36.0
        var bottom = 36.0
        var topAngle = 0.0
        var bottomAngle = 0.0
        var scaleX = 1.0
        var scaleY = 1.0
        var opacity = 1.0
        var cursor = 0.0
        var heart = 0.0
        var star = 0.0
        var smile = 0.0
    }
    struct Frame {
        var eyes = [Eye(x: -34), Eye(x: 34)]
        var headX = 0.0
        var headY = 0.0
        var headScale = 1.0
        var headRotation = 0.0
        var antennaOpacity = 1.0
        var antennaOffsetX = 0.0
        var antennaOffsetY = 0.0
    }
    static func clamp(_ t: Double) -> Double { max(0, min(1, t)) }
    static func smooth(_ t: Double) -> Double { let t = clamp(t); return t * t * (3 - 2 * t) }
    static func quint(_ t: Double) -> Double { 1 - pow(1 - clamp(t), 5) }
    static func cubic(_ t: Double) -> Double {
        let t = clamp(t)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
    static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func move(_ t: Double, _ a: Double, _ b: Double, _ from: Double, _ to: Double) -> Double {
        mix(from, to, smooth((t - a) / (b - a)))
    }
    static func bezier(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func c(_ u: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - u) * (1 - u) * u * a + 3 * (1 - u) * u * u * b + u * u * u
        }
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 { let mid = (lo + hi) / 2; if c(mid, x1, x2) < clamp(t) { lo = mid } else { hi = mid } }
        return c((lo + hi) / 2, y1, y2)
    }
    static let inspectLengths = [220.0, 880, 400, 560, 160, 580, 140, 760, 140, 620, 180, 620, 100, 940, 260]
    static var inspectEnds: [Double] {
        var cursor = 0.0
        return inspectLengths.map { cursor += $0; return cursor }
    }
    static func duration(_ action: RobotAvatarAction) -> Double {
        switch action {
        case .idle, .input, .thinking, .recalling, .working, .delegating, .replying, .awaitingConfirmation: return .infinity
        case .bored: return 3920
        case .waiting: return 3320
        case .waitingWrap: return 2520
        case .send: return 1460
        case .warning: return 3607
        case .inspect: return 280 + inspectLengths.reduce(0, +) + 30
        case .error: return 1840
        case .surprise: return 1760
        case .love, .random: return RobotSpecialMotion.duration(action: action)
        case .starEyes: return BotAvatarStarEyesMotion.durationMS
        case .smile: return BotAvatarSmileMotion.durationMS
        case .success: return 2000
        case .failure: return 2720
        case .blocked: return 1980
        case .sleep: return 4100
        case .wake: return 750
        }
    }
    /// Let finite actions finish and settle; continuous states get a visible observation window.
    static func demoDuration(_ action: RobotAvatarAction) -> Double {
        action.descriptor.demoMS
    }
    static func sample(_ action: RobotAvatarAction, ms: Double, reduced: Bool = false) -> Frame {
        var f = Frame()
        // Reduced motion retains representative eyes but removes flashing and spatial movement.
        let t = reduced ? staticTime(action) : max(0, ms)
        switch action {
        case .thinking,.recalling,.working,.delegating,.replying,.awaitingConfirmation:
            f = BotAvatarWorkMotion.sample(action,ms:t,reduced:reduced)
        case .idle: break
        case .bored:
            let u = t - 800
            let x: Double, y: Double
            if u < 0 { x = 0; y = 0 }
            else if u < 1400 {
                let k = 1 - pow(0.5, u / 16.67); x = -18 * k; y = -16 * k
            } else if u < 2800 {
                let k = 1 - pow(0.5, (u - 1400) / 16.67); x = mix(-18, 18, k); y = -16
            } else { let k = 1 - pow(0.5, (u - 2800) / 16.67); x = 18 * (1 - k); y = -16 * (1 - k) }
            for i in 0..<2 { f.eyes[i].x += x; f.eyes[i].y += y }
            f.headRotation = (x / 48) * (y / 34) * 8
        case .waiting:
            guard t >= 120, t <= 3320 else { break }
            let angle = (t - 120) / 3200 * .pi * 4
            let foreshorten = 0.72 + 0.28 * abs(cos(angle))
            for i in 0..<2 {
                let side = i == 0 ? -1.0 : 1.0
                let depth = 1 - side * 0.08 * sin(angle)
                f.eyes[i].x = side * 34 * cos(angle)
                f.eyes[i].scaleX = foreshorten * depth
                f.eyes[i].scaleY = depth
            }
        case .waitingWrap, .random:
            let playing = t < duration(action)
            let poses = RobotSpecialMotion.eyes(action: action, milliseconds: action == .waitingWrap ? max(0, t - 120) : t,
                                                reduced: reduced, playing: playing)
            if playing || reduced {
                for i in 0..<2 {
                    f.eyes[i].x = poses[i].x; f.eyes[i].y = poses[i].y
                    f.eyes[i].width = poses[i].width; f.eyes[i].height = poses[i].height
                }
            }
        case .input:
            let morph = quint((t - 140) / 210)
            for i in 0..<2 {
                f.eyes[i].width = mix(54, 12, morph); f.eyes[i].height = mix(58, 78, morph)
                f.eyes[i].top = mix(-36, -44, morph); f.eyes[i].bottom = mix(36, 44, morph)
                f.eyes[i].cursor = t >= 140 ? 1 : 0
                // Both original eye groups meet at the center to form the Demo's cursor.
                f.eyes[i].x *= 1 - morph
                if t >= 140 { f.eyes[i].opacity = reduced || Int((t - 140) / 265) % 2 == 0 ? 1 : 0 }
            }
        case .send:
            let u = t - 500
            let depth: Double
            if u < 0 { depth = 0 }
            else if u < 150 { depth = u / 150 }
            else if u < 300 { depth = 1 - (u - 150) / 150 }
            else if u < 450 { depth = (u - 300) / 150 }
            else { depth = max(0, 1 - (u - 450) / 310) }
            for i in 0..<2 { f.eyes[i].y += 31 * depth; f.eyes[i].height *= 1 - 0.30 * depth }
            // The eyes lead two nods. The head follows with two smaller dips.
            f.headY = 5 * depth
        case .warning: warning(t - 480, frame: &f)
        case .inspect: inspect(t - 280, frame: &f)
        case .error:
            let u = t - 420
            if u >= 0, u <= 980 {
                let q = u / 980
                let x: Double
                if q < 0.16 { x = move(q, 0, 0.16, 0, -1) }
                else if q < 0.40 { x = move(q, 0.16, 0.40, -1, 1) }
                else if q < 0.64 { x = move(q, 0.40, 0.64, 1, -0.88) }
                else if q < 0.84 { x = move(q, 0.64, 0.84, -0.88, 0.58) }
                else { x = move(q, 0.84, 1, 0.58, 0) }
                for i in 0..<2 { f.eyes[i].x += x * 30 }
            }
            if u >= 0, u < 1380 {
                let q = u / 1380
                if q < 0.34 { f.headX = -4 * bezier(q / 0.34, 0.38, 0, 0.28, 1) }
                else if q < 0.72 { f.headX = mix(-4, 4, bezier((q - 0.34) / 0.38, 0.35, 0, 0.22, 1)) }
                else { f.headX = mix(4, 0, bezier((q - 0.72) / 0.28, 0.35, 0, 0.22, 1)) }
            }
        case .surprise:
            let u = t - 500
            var w = 54.0, h = 58.0, spread = 0.0, pulse = 1.0
            if u >= 0, u < 235 { let k = cubic(u / 235); w = mix(54, 34, k); h = mix(58, 36, k) }
            else if u >= 235, u < 410 {
                let k = quint((u - 235) / 175); w = mix(34, 68, k); h = mix(36, 68, k)
                spread = 3.4 * quint((w - 34) / 34)
                f.headScale = mix(1, 1.035, bezier((u - 235) / 175, 0.16, 1, 0.3, 1))
            } else if u >= 410, u < 830 {
                w = 68; h = 68; spread = 3.4; f.headScale = 1.035
                let k = (u - 410) / 420; pulse = 1 + 0.022 * sin(k * .pi * 8) * (1 - 0.18 * k)
            } else if u >= 830, u < 1260 {
                let k = cubic((u - 830) / 430); w = mix(68, 54, k); h = mix(68, 58, k)
                spread = 0
                f.headScale = mix(1.035, 1, bezier((u - 830) / 430, 0.16, 1, 0.3, 1))
            }
            for i in 0..<2 { f.eyes[i].width = w * pulse; f.eyes[i].height = h * pulse; f.eyes[i].x += (i == 0 ? -1 : 1) * spread }
        case .love:
            let morph: Double
            if t < 120 { morph = 0 }
            else if t < 360 { morph = smooth((t - 120) / 240) }
            else if t < 2520 { morph = 1 }
            else { morph = 1 - smooth((t - 2520) / 360) }
            let beat = RobotSpecialMotion.pulse(action: .love, milliseconds: t, reduced: reduced, playing: t < 2880)
            for i in 0..<2 { f.eyes[i].heart = morph; f.eyes[i].scaleX = beat; f.eyes[i].scaleY = beat }
        case .starEyes:
            let pose = BotAvatarStarEyesMotion.sample(milliseconds:t,reduceMotion:reduced)
            for i in 0..<2 {
                f.eyes[i].star = pose.morph
                f.eyes[i].scaleX = pose.scale
                f.eyes[i].scaleY = pose.scale
            }
        case .smile:
            let morph = BotAvatarSmileMotion.sample(milliseconds:t,reduceMotion:reduced)
            for i in 0..<2 { f.eyes[i].smile = morph }
            f.headY = -2 * morph
        case .success, .failure, .blocked: emotion(action, time: t, frame: &f)
        case .sleep:
            let lid: Double
            if t < 160 { lid = -36 }
            else if t < 1140 { lid = mix(-36, 0, cubic((t - 160) / 940)) }
            else if t < 1260 { lid = mix(0, -22, quint((t - 1140) / 105)) }
            else if t < 2130 { lid = mix(-22, 0, cubic((t - 1260) / 820)) }
            else { lid = 0 }
            let k = cubic((t - 2250) / 980)
            for i in 0..<2 { f.eyes[i].width = mix(58, 62, k); f.eyes[i].height = mix(56, 10, k); f.eyes[i].top = mix(lid, -20, k); f.eyes[i].bottom = mix(36, 20, k); f.eyes[i].cursor = k }
            f.headY = 4 * k
        case .wake:
            let k = t < 260 ? quint(t / 240) : (t < 450 ? quint((t - 260) / 120) : 1 - quint((t - 450) / 300))
            for i in 0..<2 {
                if t < 260 { f.eyes[i].width = mix(62, 58, k); f.eyes[i].height = mix(10, 56, k); f.eyes[i].top = mix(-20, 0, k); f.eyes[i].cursor = 1 - k }
                else { f.eyes[i].width = mix(54, 68, k); f.eyes[i].height = mix(58, 68, k); f.eyes[i].top = mix(-36, -40, k) }
            }
            f.headY = t < 275 ? mix(4, -2, quint(t / 275)) : mix(-2, 0, quint((t - 275) / 225))
        }
        if !reduced, t < duration(action), let period = action.descriptor.antennaPeriodMS {
            let phaseTime = action.category == .work ? max(0,t-200) : t
            // Preserve the original arithmetic at exact blink boundaries (e.g. success at 880ms).
            let visibleMS = action.category == .original ? 800 * (period / 1000) : period * 0.8
            f.antennaOpacity = phaseTime.truncatingRemainder(dividingBy:period) < visibleMS ? 1 : 0
        }
        if reduced { f.headX = 0; f.headY = 0; f.headRotation = 0; f.headScale = 1 }
        return f
    }

    private static func staticTime(_ action: RobotAvatarAction) -> Double {
        switch action {
        case .input: 500
        case .bored: 0
        case .waiting, .waitingWrap: 120
        case .warning: 1100
        case .inspect: 800
        case .surprise: 1000
        case .love: 800
        case .starEyes: 1100
        case .smile: 1100
        case .sleep: 4100
        case .success: 800
        case .failure: 1400
        case .blocked: 1000
        case .wake: 450
        default: 0
        }
    }
    private static func warning(_ t: Double, frame f: inout Frame) {
        guard t >= 0, t < 3127 else { return }
        let release = t > 2900 ? 1 - smooth((t - 2900) / 227) : 1
        let k = smooth(t / 400) * release
        let press: Double
        if t < 400 { press = 0 }
        else if t < 1000 { press = move(t, 400, 520, 0, 4.2) }
        else if t < 1200 { press = move(t, 1000, 1200, 4.2, 20.5) }
        else if t < 1500 { press = 20.5 }
        else if t < 1700 { press = move(t, 1500, 1700, 20.5, -6.5) }
        else if t < 2000 { press = -6.5 }
        else if t < 2100 { press = move(t, 2000, 2100, -6.5, 4.2) }
        else if t < 2900 { press = 4.2 }
        else { press = 0 } // Upstream deliberately releases the lids in W9.
        let drop = t < 1500 ? move(t, 1000, 1200, 0, 1) : 1 - smooth((t - 1500) / 200)
        f.eyes[0].x = mix(-34, -18, k); f.eyes[0].y = mix(6, 5.5, k)
        f.eyes[0].scaleX = mix(1, 1.48, k); f.eyes[0].scaleY = mix(1, 1.40, k)
        f.eyes[1].x = mix(34, 58.5, k); f.eyes[1].y = mix(6, 14, k) + 2.4 * drop
        f.eyes[1].scaleX = mix(1, 0.78, k); f.eyes[1].scaleY = mix(1, 0.97, k)
        f.eyes[0].top = mix(-36, -10, k) + press; f.eyes[0].topAngle = 10 * k
        f.eyes[1].top = mix(-36, -18, k) + press * 0.95 + 3.5 * drop
        f.eyes[1].topAngle = -7.5 * k
        f.eyes[0].bottom = mix(36, 35.3, k); f.eyes[1].bottom = mix(36, 35.6, k)
        if t >= 1000, t < 1200 { f.headY = 5 * bezier((t - 1000) / 200, 0.38, 0, 0.25, 1) }
        else if t >= 1200, t < 1500 { f.headY = 5 }
        else if t >= 1500, t < 1700 { f.headY = mix(5, -4, bezier((t - 1500) / 200, 0.35, 0, 0.22, 1)) }
        else if t >= 1700, t < 2000 { f.headY = -4 }
        else if t >= 2000, t < 2100 { f.headY = mix(-4, 0, bezier((t - 2000) / 100, 0.35, 0, 0.22, 1)) }
    }
    private static func inspect(_ t: Double, frame f: inout Frame) {
        let e = inspectEnds
        guard t >= 0, t < e.last! else { return }
        let close = t < e[0] ? smooth(t / 220) : (t >= e[13] ? 1 - smooth((t - e[13]) / 260) : 1)
        let y: Double
        if t < e[1] { y = 0 }
        else if t < e[2] { y = move(t, e[1], e[2], 0, 16) }
        else if t < e[3] { y = 16 }
        else if t < e[4] { y = move(t, e[3], e[4], 16, -16) }
        else if t < e[5] { y = -16 }
        else if t < e[6] { y = move(t, e[5], e[6], -16, 0) }
        else if t < e[7] { y = 0 }
        else if t < e[8] { y = move(t, e[7], e[8], 0, 16) }
        else if t < e[9] { y = 16 }
        else if t < e[10] { y = move(t, e[9], e[10], 16, 0) }
        else { y = 0 }
        for i in 0..<2 { f.eyes[i].top = mix(-36, -8, close); f.eyes[i].bottom = mix(36, 8, close); f.eyes[i].y += y }
        if t >= e[1], t < e[2] { f.headY = 5 * bezier((t - e[1]) / 400, 0.38, 0, 0.25, 1) }
        else if t >= e[2], t < e[3] { f.headY = 5 }
        else if t >= e[3], t < e[4] { f.headY = mix(5, -4, bezier((t - e[3]) / 160, 0.35, 0, 0.22, 1)) }
        else if t >= e[4], t < e[5] { f.headY = -4 }
        else if t >= e[5], t < e[6] { f.headY = mix(-4, 0, bezier((t - e[5]) / 140, 0.35, 0, 0.22, 1)) }
    }
    private static func emotion(_ action: RobotAvatarAction, time: Double, frame f: inout Frame) {
        let prep = action == .failure ? 440.0 : 500.0
        let u = time - prep
        guard u >= 0 else { return }
        let recoverStart = action == .failure ? 1760.0 : 980.0
        let recover = action == .blocked ? 500.0 : 520.0
        let enter = action == .success ? 220.0 : (action == .failure ? 320.0 : 280.0)
        let k = u < recoverStart ? quint(u / enter) : 1 - quint((u - recoverStart) / recover)
        for i in 0..<2 {
            f.eyes[i].width = mix(54, 58, k)
            if action == .success { f.eyes[i].bottom = mix(36, 0, k) }
            else { f.eyes[i].top = mix(-36, -5, k); f.eyes[i].topAngle = (i == 0 ? -16 : 16) * k * (action == .blocked ? -1 : 1) }
        }
        if action == .failure {
            let d = u < 320 ? 0 : (u < 1040 ? smooth((u - 320) / 720) : (u < 1760 ? 1 : 1 - smooth((u - 1760) / 520)))
            f.headY = 5.5 * d
            for i in 0..<2 { f.eyes[i].y += 4.8 * d }
        } else if action == .success, u < 620 {
            let q = u / 620
            for i in 0..<2 { f.eyes[i].y += sin(q * .pi * 4) * 8 * (1 - 0.38 * q) }
            f.headY = u < 319.2 ? -2.4 * quint(u / 319.2) : mix(-2.4, 0, quint((u - 319.2) / 440.8))
        } else if action == .blocked, u < 980 {
            let q = min(1, u / 680)
            for i in 0..<2 { f.eyes[i].y += 4.8 * (1 - exp(-5.2 * q) * cos(8.6 * q)) }
            f.headY = u < 377.2 ? 2.6 * quint(u / 377.2) : mix(2.6, 0, quint((u - 377.2) / 442.8))
        }
    }
}
