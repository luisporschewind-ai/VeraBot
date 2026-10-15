import SwiftUI
import VeraBotCore

/// Shared production catalog. Locked silhouettes reuse the laboratory renderer.
struct BotAvatarShapePicker: View {
    @Binding var selection: BotAvatarFamilyShape
    var color: String
    var compact = false

    var body: some View {
        VStack(alignment:.leading,spacing:compact ? 6 : 12) {
            Text("形状").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: compact ? [GridItem(.adaptive(minimum:44),spacing:4)] : Array(repeating:GridItem(.flexible(),spacing:8),count:4),spacing:compact ? 4 : 8) {
                ForEach(BotAvatarFamilyShape.allCases) { shape in
                    Button { selection = shape } label: {
                        RobotAvatarView(action:.idle,size:compact ? 36 : 44,ambient:false,
                                        appearance:previewAppearance(shape),staticPreview:true)
                            // The nested avatar's drag gesture must not consume this button's tap.
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .frame(maxWidth:.infinity,minHeight:compact ? 48 : 68)
                        .background(selection == shape ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in:RoundedRectangle(cornerRadius:14))
                        .overlay {
                            RoundedRectangle(cornerRadius:14)
                                .stroke(selection == shape ? Color.accentColor : Color.clear,lineWidth:2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("形状：\(shape.title)")
                    .accessibilityAddTraits(selection == shape ? .isSelected : [])
                }
            }
        }
    }

    private func previewAppearance(_ shape:BotAvatarFamilyShape) -> BotAppearance {
        var value = BotAppearance.robotDefault
        value.familyShape = shape
        if let selected = BotAvatarColorPalette.appearanceColor(for:color) { value.palette.body = selected }
        return value
    }
}
