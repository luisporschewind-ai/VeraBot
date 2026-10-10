import Foundation

/// One phase defines the eyes, head and antenna. No independently scheduled accessory effects.
enum BotAvatarWorkMotion {
    static func enter(from: RobotAvatarMotion.Frame, to: RobotAvatarMotion.Frame, ms: Double) -> RobotAvatarMotion.Frame {
        let k = RobotAvatarMotion.smooth(ms / 200)
        func mix(_ a: Double, _ b: Double) -> Double { RobotAvatarMotion.mix(a,b,k) }
        var frame = to
        frame.headX = mix(from.headX,to.headX); frame.headY = mix(from.headY,to.headY)
        frame.headScale = mix(from.headScale,to.headScale); frame.headRotation = mix(from.headRotation,to.headRotation)
        frame.antennaOffsetX = mix(from.antennaOffsetX,to.antennaOffsetX)
        frame.antennaOffsetY = mix(from.antennaOffsetY,to.antennaOffsetY)
        // Flashing retains the target state's rule, rather than fading into a separate accessory state.
        for i in frame.eyes.indices {
            let a = from.eyes[i], b = to.eyes[i]
            frame.eyes[i].x = mix(a.x,b.x); frame.eyes[i].y = mix(a.y,b.y)
            frame.eyes[i].width = mix(a.width,b.width); frame.eyes[i].height = mix(a.height,b.height)
            frame.eyes[i].top = mix(a.top,b.top); frame.eyes[i].bottom = mix(a.bottom,b.bottom)
            frame.eyes[i].topAngle = mix(a.topAngle,b.topAngle); frame.eyes[i].bottomAngle = mix(a.bottomAngle,b.bottomAngle)
            frame.eyes[i].scaleX = mix(a.scaleX,b.scaleX); frame.eyes[i].scaleY = mix(a.scaleY,b.scaleY)
            frame.eyes[i].opacity = mix(a.opacity,b.opacity); frame.eyes[i].cursor = mix(a.cursor,b.cursor)
            frame.eyes[i].heart = mix(a.heart,b.heart)
            frame.eyes[i].star = mix(a.star,b.star)
            frame.eyes[i].smile = mix(a.smile,b.smile)
        }
        return frame
    }
    static func sample(_ action: BotAvatarState, ms: Double, reduced: Bool) -> RobotAvatarMotion.Frame {
        var f = RobotAvatarMotion.Frame()
        let time = reduced ? 1000.0 : max(0,ms)
        let period = action.descriptor.loopMS ?? 2400
        let p = max(0,time-200).truncatingRemainder(dividingBy:period)/period
        let enter = RobotAvatarMotion.smooth(time/200)
        let wave = pow(sin(.pi*p),2)*enter
        let twice = pow(sin(2 * .pi*p),2)*enter
        switch action {
        case .thinking:
            for i in 0..<2 { f.eyes[i].x -= 8*wave; f.eyes[i].y -= 9*wave; f.eyes[i].top += 14*wave }
            f.headRotation = -2*wave; f.antennaOffsetY = -2*wave
        case .recalling:
            let look = 12*sin(2 * .pi*p)*wave
            for i in 0..<2 { f.eyes[i].x += look; f.eyes[i].y -= 8*wave }
            f.headRotation = look/6; f.antennaOffsetX = look/6
        case .working:
            for i in 0..<2 { f.eyes[i].top += 12*wave; f.eyes[i].x += (i == 0 ? 1 : -1)*2*sin(2 * .pi*p)*wave; f.eyes[i].y += 2*twice }
            f.headY = 2*twice; f.antennaOffsetY = 3*twice
        case .delegating:
            let look = 10*wave, nod = pow(sin(.pi*RobotAvatarMotion.clamp((p-0.3)/0.45)),2)*enter
            for i in 0..<2 { f.eyes[i].x += look; f.eyes[i].y += 3*nod }
            f.headRotation = 1.5*wave; f.headY = 2*nod; f.antennaOffsetX = 4*wave
        case .replying:
            for i in 0..<2 { f.eyes[i].width += 2*wave; f.eyes[i].height -= 3*twice; f.eyes[i].y += 1.5*wave }
            f.headY = 1.5*wave; f.antennaOffsetY = -2*wave
        case .awaitingConfirmation:
            let nod = pow(sin(.pi*RobotAvatarMotion.clamp((p-0.65)/0.35)),2)*enter
            for i in 0..<2 { f.eyes[i].width += 2*wave; f.eyes[i].height += 3*wave; f.eyes[i].y += 2*nod }
            f.headY = 1.5*nod; f.antennaOffsetY = -wave
        default: break
        }
        if reduced { f.headX = 0; f.headY = 0; f.headRotation = 0; f.antennaOffsetX = 0; f.antennaOffsetY = 0 }
        return f
    }
}
