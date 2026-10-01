import PhotosUI
import SwiftUI
import UIKit
import VeraBotNetworking

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
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 220, height: 220)
                            .clipShape(Circle())
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
                        Button("取消") { closePreview() }
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

/// Bot 编辑页里的「从相册设置头像」。照片写入共享 AvatarStore，对话页和列表会马上换图。
struct BotAvatarPhotoControls: View {
    let botID: Int

    @Environment(AppState.self) private var app
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AvatarPhotoPicker(isEnabled: !busy) { image in
                try await upload(image)
            } label: {
                Label("从相册设置头像", systemImage: "photo")
            }
            Text("自定义照片优先于上面选择的表情。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func upload(_ image: UIImage) async throws {
        guard let data = AvatarImage.jpegData(from: image), let display = UIImage(data: data) else {
            throw APIError(status: 0, message: "无法处理这张照片")
        }
        busy = true
        defer { busy = false }
        let bot = try await app.api.uploadBotAvatar(botID: botID, jpeg: data)
        app.avatars.setBot(id: botID, image: display, updatedAt: bot.avatarUpdatedAt)
        errorText = nil
    }
}
