import SwiftUI
import VeraBotCore

enum BotAvatarTemplateGeometry {
    static func head(template: BotAvatarTemplate, parameters: BotAppearance.Parameters, interaction: RobotAvatarInteraction) -> Path {
        switch template.geometry {
        case .cxRobot: RobotAvatarGeometry.head(roundness:parameters.roundness,interaction:interaction)
        }
    }
}

extension BotAppearanceColor {
    var swiftUIColor: Color {
        Color(space == .displayP3 ? .displayP3 : .sRGB,red:red,green:green,blue:blue)
    }
}
