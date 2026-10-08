import Foundation
import CoreGraphics

// Native port of upstream 0.5.2 core drag-jelly and gestures (MIT).
// Coordinates are in the original 240-unit viewport; thresholds are physical points.
struct RobotAvatarInteraction {
    enum Kind { case none, pendingSqueeze, head, antenna, squeeze }
    enum Reaction { case success, angry }
    struct Spring {
        var position = 0.0
        var velocity = 0.0
        mutating func step(target: Double = 0, stiffness: Double, damping: Double, dt: Double) {
            velocity += ((target - position) * stiffness - velocity * damping) * dt
            position += velocity * dt
        }
        mutating func follow(_ target: Double, amount: Double) { position += (target - position) * amount }
    }
    private(set) var kind = Kind.none
    private(set) var held = false
    private(set) var overridesAction = false
    private(set) var age = 0.0
    private(set) var releaseAge = 0.0
    private(set) var maxDistance = 0.0
    private(set) var hot = CGPoint(x: 120, y: 120)
    private(set) var home = CGPoint(x: 120, y: 12)
    private(set) var gaze = CGPoint.zero
    private(set) var look = CGPoint.zero
    private(set) var lookRotation = Spring()
    private(set) var angle = 0.0
    private(set) var anchor = CGPoint(x: 120, y: 120)
    private(set) var reaction: Reaction?
    private(set) var reactionAge = 0.0
    private var inward = false
    private var size = 160.0
    private var targetX = 0.0, targetY = 0.0, targetStretch = 0.0, targetShear = 0.0
    private var targetPullX = 0.0, targetPullY = 0.0
    private(set) var x = Spring(), y = Spring(), stretch = Spring(), shear = Spring()
    private(set) var pullX = Spring(), pullY = Spring(), headX = Spring(), headY = Spring()
    private(set) var squeeze = Spring()
    private var pressure = 0.0, apex = 0.0, releaseDepth = 1.0

    var committed: Bool { kind != .none && kind != .pendingSqueeze }
    private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, x)) }

    mutating func begin(at point: CGPoint, size: Double, antenna: CGPoint, antennaVisible: Bool, reduced: Bool, antennaRadius: Double = 15) {
        self = Self()
        self.size = max(1, size); hot = point; home = antenna; held = true
        let radius = max(10, antennaRadius * size / 240 + 3) * 240 / max(1, size)
        if antennaVisible && hypot(point.x - antenna.x, point.y - antenna.y) <= radius {
            kind = .antenna; overridesAction = true
        } else if hypot(point.x - 120, point.y - 120) <= 240 * 0.32 {
            kind = reduced ? .squeeze : .pendingSqueeze
            overridesAction = reduced
        } else { kind = .head }
        move(translation: .zero, reduced: reduced)
    }

    mutating func move(translation: CGSize, reduced: Bool) {
        guard held else { return }
        let dx = Double(translation.width), dy = Double(translation.height), distance = hypot(dx, dy)
        maxDistance = max(maxDistance, distance)
        // Preserve the original grab point when a press becomes a drag.
        if (kind == .pendingSqueeze || kind == .squeeze) && distance > 4 {
            kind = .head; squeeze = Spring(); pressure = 0; age = 0
        }
        if kind == .head && distance > 2.5 { overridesAction = true }
        let px = dx * 240 / size, py = dy * 240 / size
        let threshold = clamp(size * 0.4, 24, 46)
        let gain = distance > threshold * 0.6 ? 0.24 : 0.19
        targetPullX = clamp(px * gain, -25, 25); targetPullY = clamp(py * gain, -25, 25)
        targetX = clamp(dx * 0.065, -5.2, 5.2); targetY = clamp(dy * 0.065, -5.2, 5.2)
        let rx = hot.x - 120, ry = hot.y - 120, length = max(1, hypot(rx, ry))
        let ux = rx / length, uy = ry / length
        let radial = px * ux + py * uy, tangent = -px * uy + py * ux
        inward = radial < -6
        angle = atan2(py, px)
        targetStretch = clamp(radial / 240 * 0.08, -0.028, 0.052)
        targetShear = clamp(tangent / 240 * 0.05, -0.022, 0.022)
        anchor = CGPoint(x: clamp(50 - ux * 31, 15, 85) * 2.4,
                         y: clamp(50 - uy * 31, 15, 85) * 2.4)
        if kind == .antenna || kind == .head {
            gaze = CGPoint(x: clamp((hot.x + px - 120) * size / 240 * 0.42, -48, 48),
                           y: clamp((hot.y + py - 120) * size / 240 * 0.38, -34, 34))
        }
        if reduced { advance(dt: 0, reduced: true) }
    }

    /// Returns true only for a short, stationary tap; dragging/pressing never replays an action.
    mutating func end(reduced: Bool) -> Bool {
        guard held else { return false }
        held = false; releaseAge = 0; releaseDepth = min(1, abs(squeeze.position))
        let tap = !overridesAction && maxDistance <= 2.5
        if kind == .pendingSqueeze || tap { kind = .none }
        if reduced {
            finish()
            // The view has no animation tick in Reduce Motion. Release the temporary
            // static feedback immediately, so the selected state's expression resumes.
            overridesAction = false
            reaction = nil
            reactionAge = 2000
        }
        return tap
    }

    mutating func advance(dt: Double, reduced: Bool) {
        reactionAge += dt * 1000
        if kind == .none {
            if reaction == nil || reactionAge >= 2000 { overridesAction = false; reaction = nil }
            return
        }
        let dt = min(0.034, max(0, dt))
        age += dt
        if !held { releaseAge += dt }
        if kind == .head || kind == .antenna {
            let gain = reduced ? 1 : 1 - pow(0.58, dt / 0.01667)
            look.x += ((held ? gaze.x : 0) - look.x) * gain
            look.y += ((held ? gaze.y : 0) - look.y) * gain
            if kind == .head && !reduced {
                lookRotation.step(target: clamp(look.x / 48, -1, 1) * clamp(look.y / 34, -1, 1) * 8,
                                  stiffness: 56, damping: 13, dt: dt)
            }
        }
        if kind == .pendingSqueeze {
            guard age >= 0.14 else { return }
            kind = .squeeze; overridesAction = true
        }
        if reduced {
            x.position = held ? targetX : 0; y.position = held ? targetY : 0
            pullX.position = held ? targetPullX : 0; pullY.position = held ? targetPullY : 0
            stretch.position = held ? targetStretch : 0; shear.position = held ? targetShear : 0
            if kind == .antenna {
                x.position = pullX.position; y.position = pullY.position
                headX.position = x.position * 0.45; headY.position = y.position * 0.45
            }
            squeeze.position = held && kind == .squeeze ? 1 : 0
            return
        }
        if kind == .head && held {
            let k = 0.36 + 0.30 * min(1, dt * 1000 / 14)
            x.follow(targetX, amount: k); y.follow(targetY, amount: k)
            stretch.follow(targetStretch, amount: k * 0.85); shear.follow(targetShear, amount: k * 0.80)
            pullX.follow(targetPullX, amount: k * 0.95); pullY.follow(targetPullY, amount: k * 0.95)
        } else {
            let oldV = squeeze.velocity
            var remaining = dt
            while remaining > 0 {
                let h = min(1 / 240.0, remaining); remaining -= h
                switch kind {
                case .squeeze:
                    let omega = 6 / 0.57
                    squeeze.step(target: held ? 1 : 0, stiffness: held ? omega * omega : 190,
                                 damping: held ? 2 * omega : 9, dt: h)
                case .antenna:
                    let settle = clamp((releaseAge - 0.45) / 0.35, 0, 1)
                    if held {
                        x.follow(targetPullX, amount: 1 - exp(-45 * h))
                        y.follow(targetPullY, amount: 1 - exp(-45 * h))
                        x.velocity = 0; y.velocity = 0
                    } else {
                        x.step(stiffness: 460, damping: 10 + 14 * settle, dt: h)
                        y.step(stiffness: 460, damping: 10 + 14 * settle, dt: h)
                    }
                    headX.step(target: held ? x.position * 0.45 : 0, stiffness: held ? 118 : 330,
                               damping: held ? 7.1 : 10 + 12 * settle, dt: h)
                    headY.step(target: held ? y.position * 0.45 : 0, stiffness: held ? 118 : 330,
                               damping: held ? 7.1 : 10 + 12 * settle, dt: h)
                case .head:
                    x.step(stiffness: 135, damping: 8.2, dt: h); y.step(stiffness: 135, damping: 8.2, dt: h)
                    stretch.step(stiffness: 128, damping: 7.5, dt: h); shear.step(stiffness: 118, damping: 7.2, dt: h)
                    pullX.step(stiffness: 118, damping: 7.1, dt: h); pullY.step(stiffness: 118, damping: 7.1, dt: h)
                default: break
                }
            }
            if kind == .squeeze && !held && apex == 0 && oldV < 0 && squeeze.velocity >= 0 && squeeze.position < 0 { apex = age }
        }
        if held && kind == .squeeze { pressure = clamp((squeeze.position - 0.94) / 0.06, 0, 1) }
        if !held {
            let values: [Spring]
            switch kind {
            case .squeeze: values = [squeeze]
            case .antenna: values = [x, y, headX, headY]
            default: values = [x, y, stretch, shear, pullX, pullY]
            }
            let reacted = kind == .head && maxDistance >= max(clamp(size * 0.4, 24, 46) * 0.76, 22)
                && abs(x.position) < 0.34 && abs(y.position) < 0.34 && abs(stretch.position) < 0.008
                && abs(shear.position) < 0.0035 && abs(pullX.position) < 0.40 && abs(pullY.position) < 0.40
            let positionTolerance = kind == .antenna ? 0.025 : 0.0015
            let velocityTolerance = kind == .antenna ? 0.06 : 0.018
            let settled = values.allSatisfy { abs($0.position) < positionTolerance && abs($0.velocity) < velocityTolerance }
            if releaseAge > 0.35 && (reacted || settled) { finish() }
        }
    }

    private mutating func finish() {
        if (kind == .antenna && maxDistance > 2.5) || (kind == .head && maxDistance >= max(clamp(size * 0.4, 24, 46) * 0.76, 22)) {
            reaction = kind == .head && inward ? .success : .angry
            reactionAge = 0
        }
        kind = .none
    }

    var squeezePose: (x: Double, y: Double, scaleX: Double, scaleY: Double, antenna: CGPoint) {
        let phase = age * 2 * Double.pi
        let jitter = 2 * pressure * (held ? 1 : exp(-releaseAge * 20))
        let ripple = apex > 0 ? 0.012 * exp(-(age - apex) * 12) * sin((age - apex) * 72) * releaseDepth : 0
        let jelly = jitter * 0.005 * sin(phase * 11) + ripple, scale = 1 - 0.29 * squeeze.position
        return (jitter * (0.7 * sin(phase * 13) + 0.3 * sin(phase * 19)), jitter * 0.45 * sin(phase * 17),
                scale + jelly, scale - jelly,
                CGPoint(x: home.x + jitter * 0.6 * sin(phase * 11 - 0.5), y: home.y + (1 - scale + jelly) * 78 - squeeze.velocity * 0.5))
    }

    func deformation(at point: CGPoint) -> CGPoint {
        guard kind == .head || kind == .antenna else { return .zero }
        let px = kind == .antenna ? clamp(headX.position, -25, 25) : pullX.position
        let py = kind == .antenna ? clamp(headY.position, -25, 25) : pullY.position
        let center = kind == .antenna ? CGPoint(x: home.x, y: clamp(home.y, 20, 220)) : hot
        let radius = (50 + hypot(px, py) * 0.8) * 0.92
        let weight = exp(-(pow(point.x - center.x, 2) + pow(point.y - center.y, 2)) / (2 * radius * radius))
        return CGPoint(x: px * weight, y: py * weight)
    }

    func reactionFrame(reduced: Bool) -> RobotAvatarMotion.Frame {
        var frame = RobotAvatarMotion.Frame()
        guard let reaction, !reduced else { return frame }
        let t = reactionAge, happy = reaction == .success
        let returnDuration = happy ? 520.0 : 500.0
        let amount = RobotAvatarMotion.quint(t / 180) * (1 - RobotAvatarMotion.quint((t - 980) / returnDuration))
        for i in 0..<2 {
            frame.eyes[i].width += 4 * amount
            if happy {
                frame.eyes[i].bottom -= 36 * amount
                if t < 620 { frame.eyes[i].y += sin(t / 620 * .pi * 4) * 8 * (1 - 0.38 * t / 620) }
            } else {
                frame.eyes[i].top += 31 * amount
                frame.eyes[i].topAngle = (i == 0 ? 16 : -16) * amount
                if t < 980 {
                    let settle = min(1, t / 680)
                    frame.eyes[i].y += 4.8 * (1 - exp(-5.2 * settle) * cos(8.6 * settle))
                } else { frame.eyes[i].y += 4.8 * (1 - RobotAvatarMotion.quint((t - 980) / returnDuration)) }
            }
        }
        let duration = happy ? 760.0 : 820.0, peak = happy ? 0.42 : 0.46
        let phase = t / duration
        if phase < 1 {
            let depth = phase < peak ? RobotAvatarMotion.smooth(phase / peak) : 1 - RobotAvatarMotion.smooth((phase - peak) / (1 - peak))
            frame.headY = (happy ? -2.4 : 2.6) * depth
        }
        return frame
    }
}
