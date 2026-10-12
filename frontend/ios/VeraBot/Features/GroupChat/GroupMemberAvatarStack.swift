import SwiftUI
import VeraBotCore

struct GroupMemberAvatarStack: View {
    let members: [ChatGroupMember]
    var size: CGFloat = 34
    var overlap: CGFloat = 18

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(members.prefix(4).enumerated()), id: \.offset) { item in
                GroupMemberAvatar(member: item.element, size: size)
                    .zIndex(Double(4 - item.offset))
            }
        }
        .frame(height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(members.map(\.name).joined(separator: "、"))
    }
}
