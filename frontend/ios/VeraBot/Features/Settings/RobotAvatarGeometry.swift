import SwiftUI

// Exact baseline points and flatten/roundness transformation from upstream 0.5.2 (MIT).
enum RobotAvatarGeometry {
    private static let baseline: [CGPoint] = [
        CGPoint(x: 120.0, y: 20.0),CGPoint(x: 132.8, y: 20.05),CGPoint(x: 139.87, y: 20.2),CGPoint(x: 145.68, y: 20.44),
        CGPoint(x: 150.79, y: 20.78),CGPoint(x: 155.43, y: 21.22),CGPoint(x: 159.71, y: 21.76),CGPoint(x: 163.69, y: 22.4),
        CGPoint(x: 167.44, y: 23.14),CGPoint(x: 170.99, y: 23.97),CGPoint(x: 174.34, y: 24.9),CGPoint(x: 177.53, y: 25.93),
        CGPoint(x: 180.57, y: 27.07),CGPoint(x: 183.46, y: 28.3),CGPoint(x: 186.22, y: 29.63),CGPoint(x: 188.85, y: 31.06),
        CGPoint(x: 191.36, y: 32.59),CGPoint(x: 193.75, y: 34.22),CGPoint(x: 196.03, y: 35.96),CGPoint(x: 198.19, y: 37.8),
        CGPoint(x: 200.25, y: 39.75),CGPoint(x: 202.2, y: 41.81),CGPoint(x: 204.04, y: 43.97),CGPoint(x: 205.78, y: 46.25),
        CGPoint(x: 207.41, y: 48.64),CGPoint(x: 208.94, y: 51.15),CGPoint(x: 210.37, y: 53.78),CGPoint(x: 211.7, y: 56.54),
        CGPoint(x: 212.93, y: 59.43),CGPoint(x: 214.07, y: 62.47),CGPoint(x: 215.1, y: 65.66),CGPoint(x: 216.03, y: 69.01),
        CGPoint(x: 216.86, y: 72.56),CGPoint(x: 217.6, y: 76.31),CGPoint(x: 218.24, y: 80.29),CGPoint(x: 218.78, y: 84.57),
        CGPoint(x: 219.22, y: 89.21),CGPoint(x: 219.56, y: 94.32),CGPoint(x: 219.8, y: 100.13),CGPoint(x: 219.95, y: 107.2),
        CGPoint(x: 220.0, y: 120.0),CGPoint(x: 219.95, y: 132.8),CGPoint(x: 219.8, y: 139.87),CGPoint(x: 219.56, y: 145.68),
        CGPoint(x: 219.22, y: 150.79),CGPoint(x: 218.78, y: 155.43),CGPoint(x: 218.24, y: 159.71),CGPoint(x: 217.6, y: 163.69),
        CGPoint(x: 216.86, y: 167.44),CGPoint(x: 216.03, y: 170.99),CGPoint(x: 215.1, y: 174.34),CGPoint(x: 214.07, y: 177.53),
        CGPoint(x: 212.93, y: 180.57),CGPoint(x: 211.7, y: 183.46),CGPoint(x: 210.37, y: 186.22),CGPoint(x: 208.94, y: 188.85),
        CGPoint(x: 207.41, y: 191.36),CGPoint(x: 205.78, y: 193.75),CGPoint(x: 204.04, y: 196.03),CGPoint(x: 202.2, y: 198.19),
        CGPoint(x: 200.25, y: 200.25),CGPoint(x: 198.19, y: 202.2),CGPoint(x: 196.03, y: 204.04),CGPoint(x: 193.75, y: 205.78),
        CGPoint(x: 191.36, y: 207.41),CGPoint(x: 188.85, y: 208.94),CGPoint(x: 186.22, y: 210.37),CGPoint(x: 183.46, y: 211.7),
        CGPoint(x: 180.57, y: 212.93),CGPoint(x: 177.53, y: 214.07),CGPoint(x: 174.34, y: 215.1),CGPoint(x: 170.99, y: 216.03),
        CGPoint(x: 167.44, y: 216.86),CGPoint(x: 163.69, y: 217.6),CGPoint(x: 159.71, y: 218.24),CGPoint(x: 155.43, y: 218.78),
        CGPoint(x: 150.79, y: 219.22),CGPoint(x: 145.68, y: 219.56),CGPoint(x: 139.87, y: 219.8),CGPoint(x: 132.8, y: 219.95),
        CGPoint(x: 120.0, y: 220.0),CGPoint(x: 107.2, y: 219.95),CGPoint(x: 100.13, y: 219.8),CGPoint(x: 94.32, y: 219.56),
        CGPoint(x: 89.21, y: 219.22),CGPoint(x: 84.57, y: 218.78),CGPoint(x: 80.29, y: 218.24),CGPoint(x: 76.31, y: 217.6),
        CGPoint(x: 72.56, y: 216.86),CGPoint(x: 69.01, y: 216.03),CGPoint(x: 65.66, y: 215.1),CGPoint(x: 62.47, y: 214.07),
        CGPoint(x: 59.43, y: 212.93),CGPoint(x: 56.54, y: 211.7),CGPoint(x: 53.78, y: 210.37),CGPoint(x: 51.15, y: 208.94),
        CGPoint(x: 48.64, y: 207.41),CGPoint(x: 46.25, y: 205.78),CGPoint(x: 43.97, y: 204.04),CGPoint(x: 41.81, y: 202.2),
        CGPoint(x: 39.75, y: 200.25),CGPoint(x: 37.8, y: 198.19),CGPoint(x: 35.96, y: 196.03),CGPoint(x: 34.22, y: 193.75),
        CGPoint(x: 32.59, y: 191.36),CGPoint(x: 31.06, y: 188.85),CGPoint(x: 29.63, y: 186.22),CGPoint(x: 28.3, y: 183.46),
        CGPoint(x: 27.07, y: 180.57),CGPoint(x: 25.93, y: 177.53),CGPoint(x: 24.9, y: 174.34),CGPoint(x: 23.97, y: 170.99),
        CGPoint(x: 23.14, y: 167.44),CGPoint(x: 22.4, y: 163.69),CGPoint(x: 21.76, y: 159.71),CGPoint(x: 21.22, y: 155.43),
        CGPoint(x: 20.78, y: 150.79),CGPoint(x: 20.44, y: 145.68),CGPoint(x: 20.2, y: 139.87),CGPoint(x: 20.05, y: 132.8),
        CGPoint(x: 20.0, y: 120.0),CGPoint(x: 20.05, y: 107.2),CGPoint(x: 20.2, y: 100.13),CGPoint(x: 20.44, y: 94.32),
        CGPoint(x: 20.78, y: 89.21),CGPoint(x: 21.22, y: 84.57),CGPoint(x: 21.76, y: 80.29),CGPoint(x: 22.4, y: 76.31),
        CGPoint(x: 23.14, y: 72.56),CGPoint(x: 23.97, y: 69.01),CGPoint(x: 24.9, y: 65.66),CGPoint(x: 25.93, y: 62.47),
        CGPoint(x: 27.07, y: 59.43),CGPoint(x: 28.3, y: 56.54),CGPoint(x: 29.63, y: 53.78),CGPoint(x: 31.06, y: 51.15),
        CGPoint(x: 32.59, y: 48.64),CGPoint(x: 34.22, y: 46.25),CGPoint(x: 35.96, y: 43.97),CGPoint(x: 37.8, y: 41.81),
        CGPoint(x: 39.75, y: 39.75),CGPoint(x: 41.81, y: 37.8),CGPoint(x: 43.97, y: 35.96),CGPoint(x: 46.25, y: 34.22),
        CGPoint(x: 48.64, y: 32.59),CGPoint(x: 51.15, y: 31.06),CGPoint(x: 53.78, y: 29.63),CGPoint(x: 56.54, y: 28.3),
        CGPoint(x: 59.43, y: 27.07),CGPoint(x: 62.47, y: 25.93),CGPoint(x: 65.66, y: 24.9),CGPoint(x: 69.01, y: 23.97),
        CGPoint(x: 72.56, y: 23.14),CGPoint(x: 76.31, y: 22.4),CGPoint(x: 80.29, y: 21.76),CGPoint(x: 84.57, y: 21.22),
        CGPoint(x: 89.21, y: 20.78),CGPoint(x: 94.32, y: 20.44),CGPoint(x: 100.13, y: 20.2),CGPoint(x: 107.2, y: 20.05),
    ]
    static func head(roundness: Double, interaction: RobotAvatarInteraction = .init()) -> Path {
        let points = baseline.map { point -> CGPoint in
            let y = Double(point.y)
            var shift = 0.0
            if y <= 100 { shift = 10 }
            else if y < 120 { shift = 10 * RobotAvatarMotion.smooth((120 - y) / 20) }
            else if y >= 140 { shift = -10 }
            else if y > 120 { shift = -10 * RobotAvatarMotion.smooth((y - 120) / 20) }
            return CGPoint(x: point.x, y: y + shift)
        }
        let amount = abs(roundness - 0.5) * 2
        let exponent = roundness < 0.5 ? 10.0 : 2.2
        var path = Path()
        for (index, point) in points.enumerated() {
            let angle = atan2(Double(point.y) - 120, Double(point.x) - 120)
            let x = cos(angle), y = sin(angle)
            let denominator = pow(pow(abs(x) / 100, exponent) + pow(abs(y) / 90, exponent), 1 / exponent)
            let target = CGPoint(x: 120 + x / denominator, y: 120 + y / denominator)
            let base = CGPoint(x: point.x + (target.x - point.x) * amount,
                               y: point.y + (target.y - point.y) * amount)
            let offset = interaction.deformation(at: base)
            let p = CGPoint(x: 7.2 + (base.x + offset.x) * 0.94,
                            y: 7.2 + (base.y + offset.y) * 0.94)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    static func eye(_ eye: RobotAvatarMotion.Eye, blink: Double) -> Path {
        if eye.cursor > 0.999 {
            return Path(roundedRect: CGRect(x: -eye.width / 2, y: -eye.height / 2,
                                            width: eye.width, height: eye.height), cornerRadius: 3)
        }
        let height = max(2.6, eye.height * blink)
        let adjust = (eye.height - height) * 0.02
        var points = (0..<128).map { index -> CGPoint in
            let angle = Double(index) / 128 * Double.pi * 2
            return CGPoint(x: cos(angle) * eye.width / 2, y: sin(angle) * height / 2 + adjust)
        }
        // Clip the ellipse against the two rotated mask edges, preserving its curved sides.
        points = clip(points, edge: eye.top, angle: eye.topAngle, above: false)
        points = clip(points, edge: eye.bottom, angle: eye.bottomAngle, above: true)
        var path = Path()
        for (i, p) in points.enumerated() { if i == 0 { path.move(to: p) } else { path.addLine(to: p) } }
        path.closeSubpath()
        return path
    }
    private static func clip(_ points: [CGPoint], edge: Double, angle: Double, above: Bool) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let slope = tan(angle * Double.pi / 180)
        func distance(_ p: CGPoint) -> Double { (p.y - edge - p.x * slope) * (above ? -1 : 1) }
        var result = [CGPoint](), previous = points.last!
        var d0 = distance(previous)
        for p in points {
            let d1 = distance(p)
            if (d0 >= 0) != (d1 >= 0) {
                let t = d0 / (d0 - d1)
                result.append(CGPoint(x: previous.x + (p.x - previous.x) * t, y: previous.y + (p.y - previous.y) * t))
            }
            if d1 >= 0 { result.append(p) }
            previous = p; d0 = d1
        }
        return result
    }

    // Two independent hearts are the user's requested variation from the single-heart Demo.
    static func heart(_ eye: RobotAvatarMotion.Eye) -> Path {
        let k = eye.heart, w = eye.width / 2, h = eye.height / 2 * (1 - 0.08 * k)
        func p(_ ellipse: CGPoint, _ heart: CGPoint) -> CGPoint {
            CGPoint(x: (ellipse.x + (heart.x - ellipse.x) * k) * w,
                    y: (ellipse.y + (heart.y - ellipse.y) * k) * h)
        }
        // Eight segments give each lobe a full rounded arc. Matching tangents at
        // every join also keep the notch and bottom tip smooth throughout the morph.
        let segments: [(end: CGPoint, c1: CGPoint, c2: CGPoint)] = [
            (CGPoint(x: 0.5, y: -1), CGPoint(x: 0.16, y: -0.58), CGPoint(x: 0.20, y: -1)),
            (CGPoint(x: 1, y: -0.45), CGPoint(x: 0.80, y: -1), CGPoint(x: 1, y: -0.80)),
            (CGPoint(x: 0.18, y: 0.87), CGPoint(x: 1, y: -0.10), CGPoint(x: 0.28, y: 0.79)),
            (CGPoint(x: 0, y: 0.96), CGPoint(x: 0.08, y: 0.95), CGPoint(x: 0.06, y: 0.96)),
            (CGPoint(x: -0.18, y: 0.87), CGPoint(x: -0.06, y: 0.96), CGPoint(x: -0.08, y: 0.95)),
            (CGPoint(x: -1, y: -0.45), CGPoint(x: -0.28, y: 0.79), CGPoint(x: -1, y: -0.10)),
            (CGPoint(x: -0.5, y: -1), CGPoint(x: -1, y: -0.80), CGPoint(x: -0.80, y: -1)),
            (CGPoint(x: 0, y: -0.58), CGPoint(x: -0.20, y: -1), CGPoint(x: -0.16, y: -0.58)),
        ]
        let step = Double.pi / 4, tangent = 4.0 / 3 * tan(Double.pi / 16)
        var path = Path()
        path.move(to: p(CGPoint(x: 0, y: -1), CGPoint(x: 0, y: -0.58)))
        for (index, segment) in segments.enumerated() {
            let from = -Double.pi / 2 + Double(index) * step, to = from + step
            let start = CGPoint(x: cos(from), y: sin(from)), end = CGPoint(x: cos(to), y: sin(to))
            let c1 = CGPoint(x: start.x - sin(from) * tangent, y: start.y + cos(from) * tangent)
            let c2 = CGPoint(x: end.x + sin(to) * tangent, y: end.y - cos(to) * tangent)
            path.addCurve(to: p(end, segment.end), control1: p(c1, segment.c1), control2: p(c2, segment.c2))
        }
        path.closeSubpath()
        return path
    }

    /// Morph the open ellipse into a rounded upward smile, preserving both curved ends.
    static func crescent(_ eye: RobotAvatarMotion.Eye) -> Path {
        let morph = RobotAvatarMotion.clamp(eye.smile)
        var path = Path()
        for index in 0..<128 {
            let angle = Double(index) / 128 * .pi * 2
            let u = cos(angle)
            let openY = sin(angle) * eye.height / 2
            let smileY = -8 + 12 * u * u + sin(angle) * 5
            let point = CGPoint(x:u * eye.width / 2,
                                y:RobotAvatarMotion.mix(openY,smileY,morph))
            if index == 0 { path.move(to:point) } else { path.addLine(to:point) }
        }
        path.closeSubpath()
        return path
    }

    static func star(_ eye: RobotAvatarMotion.Eye, progress: Double) -> Path {
        let morph = RobotAvatarMotion.clamp(progress)
        let innerRadius = RobotAvatarMotion.mix(1,0.46,morph)
        let points = (0..<10).map { index -> CGPoint in
            let angle = -Double.pi / 2 + Double(index) * .pi / 5
            let radius = index.isMultiple(of:2) ? 1.0 : innerRadius
            return CGPoint(x:cos(angle) * radius * eye.width / 2,
                           y:sin(angle) * radius * eye.height / 2)
        }
        func blend(_ a:CGPoint,_ b:CGPoint,_ amount:CGFloat) -> CGPoint {
            CGPoint(x:a.x + (b.x-a.x)*amount,y:a.y + (b.y-a.y)*amount)
        }
        var path = Path()
        path.move(to:blend(points[9],points[0],0.18))
        for index in points.indices {
            let current = points[index], next = points[(index+1) % points.count]
            path.addQuadCurve(to:blend(current,next,0.18),control:current)
        }
        path.closeSubpath()
        return path
    }
}
