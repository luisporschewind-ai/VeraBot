import SwiftUI
import VeraBotCore

/// Curated silhouettes reuse the original local deformation and coordinate space.
enum RobotAvatarFamilyGeometry {
    static func head(seed:UInt32,roundness:Double,interaction:RobotAvatarInteraction) -> Path {
        var path = Path()
        for (index,point) in BotAvatarFamilySilhouette.points(seed:seed,roundness:roundness).enumerated() {
            let base = CGPoint(x:point.x,y:point.y)
            let offset = interaction.deformation(at:base)
            let deformed = CGPoint(x:7.2 + (base.x + offset.x) * 0.94,
                                   y:7.2 + (base.y + offset.y) * 0.94)
            if index == 0 { path.move(to:deformed) } else { path.addLine(to:deformed) }
        }
        path.closeSubpath()
        return path
    }

    static func antenna(seed:UInt32,roundness:Double) -> CGPoint {
        let top = BotAvatarFamilySilhouette.points(seed:seed,roundness:roundness)[0]
        // Preserve the standard member's gap and full antenna diameter above the body.
        return CGPoint(x:120,y:7.2 + top.y * 0.94 - 23.4)
    }
}
