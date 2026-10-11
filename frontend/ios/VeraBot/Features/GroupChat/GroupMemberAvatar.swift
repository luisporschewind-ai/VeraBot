import SwiftUI
import VeraBotCore

struct GroupMemberAvatar: View {
    let member: ChatGroupMember
    var size: CGFloat = 42
    var action: BotAvatarState = .idle

    private var appearance: BotAppearance? {
        guard let value = member.appearance, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(BotAppearance.self, from: data)
    }
    var body: some View {
        RobotAvatarView(action: action, size: size, color: Color(hex: member.color), ambient: false, appearance: appearance)
            .accessibilityLabel(member.name)
    }
}
