import SwiftUI

/// 用户头像：用户名首字母 + 品牌色圆形。
struct UserAvatar: View {
    let username: String
    var size: CGFloat = 32

    var body: some View {
        Text(String(username.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.brand, in: Circle())
    }
}
