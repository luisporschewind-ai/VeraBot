import SwiftUI
import VeraBotCore

/// A conversation-sized portrait: the current user first, then up to three Bots.
struct GroupConversationAvatar: View {
    let members: [ChatGroupMember]
    var size: CGFloat = 44

    @Environment(AppState.self) private var app

    private var visibleMembers: [ChatGroupMember] { Array(members.prefix(3)) }
    private var count: Int { visibleMembers.count + 1 }
    private var portraitSize: CGFloat { size * (count == 1 ? 1 : count == 2 ? 26.0 / 44 : 25.0 / 44) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<count, id: \.self) { index in
                portrait(at: index)
                    .frame(width: portraitSize, height: portraitSize)
                    .compositingGroup()
                    // Outline the actual silhouette, preserving each Bot's shape.
                    .shadow(color: .appBackground, radius: 0, x: -0.5, y: 0)
                    .shadow(color: .appBackground, radius: 0, x: 0.5, y: 0)
                    .shadow(color: .appBackground, radius: 0, x: 0, y: -0.5)
                    .shadow(color: .appBackground, radius: 0, x: 0, y: 0.5)
                    .position(center(at: index))
                    .zIndex(Double(index))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([app.displayName] + members.map(\.name)).joined(separator: "、"))
    }

    @ViewBuilder private func portrait(at index: Int) -> some View {
        if index == 0 {
            UserAvatar(name: app.displayName, image: app.avatars.userImage, size: portraitSize)
        } else {
            GroupMemberAvatar(member: visibleMembers[index - 1], size: portraitSize)
        }
    }

    private func center(at index: Int) -> CGPoint {
        // Leave room for the Bot antenna and its silhouette outline at the edges.
        let inset = portraitSize / 2 + (count >= 3 ? size / 44 : 0)
        let far = size - inset
        switch count {
        case 1:
            return CGPoint(x: size / 2, y: size / 2)
        case 2:
            return CGPoint(x: index == 0 ? inset : far, y: size / 2)
        case 3:
            if index == 0 { return CGPoint(x: size / 2, y: inset) }
            return CGPoint(x: index == 1 ? inset : far, y: far)
        default:
            return CGPoint(x: index.isMultiple(of: 2) ? inset : far,
                           y: index < 2 ? inset : far)
        }
    }
}
