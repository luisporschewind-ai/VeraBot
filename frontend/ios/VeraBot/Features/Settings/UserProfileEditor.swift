import SwiftUI
import UIKit
import VeraBotCore
import VeraBotNetworking

/// 设置页「账号」分组：点头像从相册更换，点昵称弹窗修改。服务器地址见调试页。改完写入 AppState，首页和对话立刻跟着变。
struct AccountSettingsSection: View {
    @Environment(AppState.self) private var app
    @State private var draft = ""
    @State private var editingNickname = false
    @State private var errorText: String?
    @State private var saving = false

    var body: some View {
        Section {
            HStack(spacing: 12) {
                // 点头像：从相册更换；点昵称：弹出系统输入框修改。两者是独立的点按区域（borderless）。
                AvatarPhotoPicker { image in
                    try await upload(image)
                } label: {
                    UserAvatar(name: app.displayName, image: app.avatars.userImage, size: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("更换头像")
                Button {
                    draft = app.displayName
                    editingNickname = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            // 按钮内 .primary 会被解析成强调色，这里显式用系统文字色，保持与普通行一致
                            Text(app.displayName).font(.headline).foregroundStyle(Color.primary)
                            Text("用户名 \(app.username ?? "")")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer(minLength: 8)
                        if saving { ProgressView() }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(saving)
                .accessibilityLabel("昵称 \(app.displayName)")
                .accessibilityHint("点按修改昵称")
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("账号")
        }
        .alert("修改昵称", isPresented: $editingNickname) {
            TextField("昵称", text: $draft)
                .textInputAutocapitalization(.never)
            Button("取消", role: .cancel) {}
            Button("保存") { Task { await saveNickname() } }
        } message: {
            Text("最多 32 个字")
        }
    }

    private func saveNickname() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned = NicknameRules.cleaned(draft) else {
            errorText = trimmed.isEmpty ? "昵称不能为空" : "昵称最多 32 个字"
            return
        }
        if cleaned == app.displayName && app.nickname != nil {
            errorText = nil
            return
        }
        saving = true
        defer { saving = false }
        do {
            let user = try await app.api.updateNickname(cleaned)
            app.applyUser(user)
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func upload(_ image: UIImage) async throws {
        guard let data = AvatarImage.jpegData(from: image), let display = UIImage(data: data) else {
            throw APIError(status: 0, message: "无法处理这张照片")
        }
        let user = try await app.api.uploadMyAvatar(jpeg: data)
        app.applyUser(user)
        app.avatars.setUser(image: display, updatedAt: user.avatarUpdatedAt)
        errorText = nil
    }
}
