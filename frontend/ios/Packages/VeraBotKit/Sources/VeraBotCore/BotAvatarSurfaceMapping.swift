import Foundation

/// Fixed surface UVs: motifs spread across the face and compress toward its rounded edges.
public enum BotAvatarSurfaceMapping {
    public static func project(_ value: Double) -> Double {
        let u = value.isFinite ? min(1,max(0,value)) : 0.5
        return 0.5 + sin((u-0.5) * .pi * 0.8) / (2 * sin(.pi * 0.4))
    }
    public static func unproject(_ value: Double) -> Double {
        let u = value.isFinite ? min(1,max(0,value)) : 0.5
        return 0.5 + asin((u-0.5) * 2 * sin(.pi * 0.4)) / (.pi * 0.8)
    }
    public struct Affine: Sendable {
        public let a, b, c, d, tx, ty: Double
    }
    public static func affine(source:[(Double,Double)],target:[(Double,Double)]) -> Affine {
        precondition(source.count == 3 && target.count == 3)
        let sx = source[1].0-source[0].0, sy = source[1].1-source[0].1
        let vx = source[2].0-source[0].0, vy = source[2].1-source[0].1
        let px = target[1].0-target[0].0, py = target[1].1-target[0].1
        let qx = target[2].0-target[0].0, qy = target[2].1-target[0].1
        let det = sx*vy-vx*sy
        guard abs(det) > 1e-12 else { return Affine(a:1,b:0,c:0,d:1,tx:0,ty:0) }
        let a = (px*vy-qx*sy)/det, b = (py*vy-qy*sy)/det
        let c = (sx*qx-vx*px)/det, d = (sx*qy-vx*py)/det
        return Affine(a:a,b:b,c:c,d:d,tx:target[0].0-a*source[0].0-c*source[0].1,ty:target[0].1-b*source[0].0-d*source[0].1)
    }
}
