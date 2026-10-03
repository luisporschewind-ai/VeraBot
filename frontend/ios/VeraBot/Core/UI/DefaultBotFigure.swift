import SwiftUI
import VeraBotCore

/// 无相册照片时的默认 Bot 形象（头像实验室的五款角色）。
struct DefaultBotFigure: View {
    let storedAvatar: String
    var pose: AvatarLabState = .idle
    var animated = false
    var size: CGFloat = 44

    var body: some View {
        AvatarLabCharacterView(
            kind: AvatarLabCharacterKind(BotAvatarFigure(stored: storedAvatar)),
            state: pose,
            size: size,
            animated: animated
        )
    }
}

/// 创建页 / Bot 详情里选择默认形象。只改 `avatar` 字段，不上传照片。
struct BotFigurePicker: View {
    let selection: BotAvatarFigure
    let onSelect: (BotAvatarFigure) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BotAvatarFigure.allCases) { figure in
                    let kind = AvatarLabCharacterKind(figure)
                    Button {
                        onSelect(figure)
                    } label: {
                        AvatarLabCharacterView(kind: kind, state: .idle, size: 44, animated: false)
                            .accessibilityHidden(true)
                            .padding(4)
                            .background(selection == figure ? Color.brandSoft : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.title)
                    .accessibilityAddTraits(selection == figure ? .isSelected : [])
                }
            }
        }
    }
}
