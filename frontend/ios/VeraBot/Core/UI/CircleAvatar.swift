import SwiftUI
import UIKit

/// 所有头像共用的正圆容器：固定等宽高的 frame + Circle 裁切，照片按 .fill 填满，
/// 表情 / 首字放在纯色圆底上。任何父视图（含导航栏按钮）给出的非正方形尺寸都不会把它压扁。
struct CircleAvatar<Fallback: View>: View {
    var image: UIImage?
    var background: Color = .clear
    let size: CGFloat
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        Circle()
            .fill(background)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                } else {
                    fallback()
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .contentShape(Circle())
            .fixedSize()
    }
}
