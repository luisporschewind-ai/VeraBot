import AVFoundation
import SwiftUI
import UIKit

/// 系统相机（UIImagePickerController, sourceType .camera）：系统默认界面，无自定义相机 / 动画。
/// 拍完把 UIImage 交给调用方，之后与相册选图走同一条 ComposerAttachmentModel / ImagePreparer 路径。
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    /// 设备有相机才显示「拍照」（模拟器 / 无相机设备隐藏）
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// 相机权限：未决定时由系统弹窗询问；返回 false 表示已拒绝 / 受限（调用方提示前往设置）
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
