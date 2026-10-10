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

enum RobotAvatarSkinRendering {
    static func antennaColor(_ skin: BotAvatarSkin) -> Color { color(skin.antennaColorHex) }

    static func draw(_ skin: BotAvatarSkin, in context: inout GraphicsContext) {
        let image = context.resolve(Image(skin.assetName))
        context.draw(image, in:CGRect(x:0,y:0,width:240,height:240))
    }

    private static func color(_ hex:String) -> Color {
        let value = UInt32(hex.dropFirst(),radix:16) ?? 0
        return Color(.sRGB,
                     red:Double((value >> 16) & 0xFF) / 255,
                     green:Double((value >> 8) & 0xFF) / 255,
                     blue:Double(value & 0xFF) / 255)
    }
}
