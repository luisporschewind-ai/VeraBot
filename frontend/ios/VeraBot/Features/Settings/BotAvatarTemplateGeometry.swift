import SwiftUI
import VeraBotCore

enum BotAvatarTemplateGeometry {
    static func head(template: BotAvatarTemplate, parameters: BotAppearance.Parameters, interaction: RobotAvatarInteraction, familyShape: BotAvatarFamilyShape = .standard) -> Path {
        if let seed = familyShape.seed {
            return RobotAvatarFamilyGeometry.head(seed:seed,roundness:parameters.roundness,interaction:interaction)
        }
        return switch template.geometry {
        case .cxRobot: RobotAvatarGeometry.head(roundness:parameters.roundness,interaction:interaction)
        }
    }
}

extension BotAppearanceColor {
    var swiftUIColor: Color {
        Color(space == .displayP3 ? .displayP3 : .sRGB,red:red,green:green,blue:blue)
    }
}

extension BotAvatarColorOption {
    var color: Color { appearanceColor.swiftUIColor }
}
