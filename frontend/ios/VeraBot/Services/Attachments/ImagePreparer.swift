import Foundation
import ImageIO
import UniformTypeIdentifiers
import VeraBotCore

/// 上传前在本机压缩好的图片。
struct PreparedImage: Sendable {
    let data: Data
    let mime: String
}

/// 上传前处理（在后台调用）：长边缩到 2048、JPEG 0.8；用 CGImageDestination 重新写出且不带原图元数据（EXIF / GPS）。
/// 带透明的图保持 PNG；GIF 原样上传（保留动画，服务器去掉注释块）。服务器还会再校验、再去 EXIF。
enum ImagePreparer {
    enum Failure: LocalizedError {
        case unreadable
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: "无法读取这张照片"
            case .tooLarge: "图片不能超过 10MB"
            }
        }
    }

    static func prepare(_ data: Data) throws -> PreparedImage {
        if AttachmentLimits.isGIF(data) {
            guard data.count <= AttachmentLimits.maxBytes else { throw Failure.tooLarge }
            return PreparedImage(data: data, mime: "image/gif")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // 按 EXIF 方向转正
            kCGImageSourceThumbnailMaxPixelSize: AttachmentLimits.maxSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw Failure.unreadable
        }
        let properties: [CFString: Any] = hasAlpha
            ? [:]
            : [kCGImageDestinationLossyCompressionQuality: AttachmentLimits.jpegQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)   // 不复制源元数据
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        let result = output as Data
        guard result.count <= AttachmentLimits.maxBytes else { throw Failure.tooLarge }
        return PreparedImage(data: result, mime: hasAlpha ? "image/png" : "image/jpeg")
    }
}
