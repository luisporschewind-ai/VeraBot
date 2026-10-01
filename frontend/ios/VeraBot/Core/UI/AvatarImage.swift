import UIKit

/// 上传前把照片收成正方形 JPEG，减小体积。服务端还会再压成 512×512。
enum AvatarImage {
    static func jpegData(from image: UIImage, maxPixel: CGFloat = 1024, quality: CGFloat = 0.82) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let side = maxPixel
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let rendered = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            let src = image.size
            guard src.width > 0, src.height > 0 else { return }
            let scale = max(side / src.width, side / src.height)
            let w = src.width * scale
            let h = src.height * scale
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        var q = quality
        var data = rendered.jpegData(compressionQuality: q)
        while let current = data, current.count > 7 * 1024 * 1024, q > 0.4 {
            q -= 0.12
            data = rendered.jpegData(compressionQuality: q)
        }
        return data
    }
}

enum AvatarInitial {
    static func text(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ch = trimmed.first else { return "?" }
        return String(ch).uppercased()
    }
}
