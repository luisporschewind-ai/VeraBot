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
            label()
        }
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
