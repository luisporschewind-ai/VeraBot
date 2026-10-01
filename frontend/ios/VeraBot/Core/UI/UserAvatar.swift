import SwiftUI
import UIKit

/// 用户头像：有自定义照片时显示圆形图片，否则是昵称首字 + 品牌色。
struct UserAvatar: View {
    let name: String
    var image: UIImage? = nil
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(AvatarInitial.text(for: name))
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.brand)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// 首页导航栏里的头像。没有照片时只放首字，由系统圆形按钮承载，不自绘背景。
struct HomeAvatarLabel: View {
    let name: String
    var image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
        } else {
            Text(AvatarInitial.text(for: name))
                .font(.headline)
                .foregroundStyle(Color.brand)
        }
    }
}
