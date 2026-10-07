import PhotosUI
import SwiftUI
import UIKit

/// 系统 PhotosPicker + 圆形预览。确认后把原图交给调用方上传；没有自定义动画。
struct AvatarPhotoPicker<Label: View>: View {
    var isEnabled: Bool = true
    let onConfirm: (UIImage) async throws -> Void
    @ViewBuilder var label: () -> Label

    @State private var selection: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var showPreview = false
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            // PhotosUI 的 SDK 将这个闭包标记为 @Sendable；保持内容静态，避免跨隔离捕获自定义 ViewBuilder。
            Color.clear
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // 头像只负责显示，picker 的透明区域承接点击并保留 PhotosPicker 的按钮无障碍语义。
        .overlay { label().frame(width: 44, height: 44).allowsHitTesting(false) }
        .disabled(!isEnabled || busy)
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            Task { await load(newValue) }
        }
        .sheet(isPresented: $showPreview, onDismiss: { preview = nil; errorText = nil }) {
            NavigationStack {
                VStack(spacing: 16) {
                    if let preview {
                        CircleAvatar(image: preview, size: 220) { EmptyView() }
                    }
                    Text("将裁成正方形，并按圆形显示")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("头像预览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        DismissToolbarButton(kind: .cancel) { closePreview() }
                            .disabled(busy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("使用") { Task { await confirm() } }
                            .disabled(busy || preview == nil)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        defer { selection = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                preview = nil
                errorText = "无法读取这张照片"
                showPreview = true
                return
            }
            errorText = nil
            preview = image
            showPreview = true
        } catch {
            preview = nil
            errorText = "无法读取这张照片"
            showPreview = true
        }
    }

    private func confirm() async {
        guard let preview, preview.size.width > 0 else { return }
        busy = true
        defer { busy = false }
        do {
            try await onConfirm(preview)
            closePreview()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func closePreview() {
        showPreview = false
        preview = nil
        errorText = nil
    }
}
