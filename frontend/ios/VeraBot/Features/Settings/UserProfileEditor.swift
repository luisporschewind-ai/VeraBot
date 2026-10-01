import SwiftUI
import UIKit
import VeraBotCore
import VeraBotNetworking

/// 设置页「账号」分组：头像（相册 / 恢复默认）、昵称、服务器。改完写入 AppState，首页和对话立刻跟着变。
struct AccountSettingsSection: View {
    @Environment(AppState.self) private var app
    @State private var draft = ""
    @State private var baseline = ""
    @State private var errorText: String?
    @State private var saving = false
    @State private var confirmRestore = false

    var body: some View {
        Section {
        HStack(spacing: 12) {
            AvatarPhotoPicker { image in
                try await upload(image)
            } label: {
                UserAvatar(name: app.displayName, image: app.avatars.userImage, size: 44)
            }
            .accessibilityLabel("更换头像")
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName).font(.headline)
                Text("用户名 \(app.username ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { syncIfClean(force: true) }
        .onChange(of: app.displayName) { _, _ in syncIfClean(force: false) }
        TextField("昵称", text: $draft)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit { Task { await saveNickname() } }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) != baseline {
            Button(saving ? "正在保存…" : "保存昵称") { Task { await saveNickname() } }
                .disabled(saving)
        }
        if app.hasAvatar || app.avatars.userImage != nil {
            Button("恢复默认头像", role: .destructive) { confirmRestore = true }
                .disabled(saving)
                .confirmationDialog("恢复默认头像？", isPresented: $confirmRestore, titleVisibility: .visible) {
                    Button("恢复默认", role: .destructive) { Task { await restore() } }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("将移除自定义头像，改回显示昵称首字。")
                }
        }
        if let errorText {
            Text(errorText).font(.footnote).foregroundStyle(.red)
        }
        LabeledContent("服务器", value: app.baseURLString)
        } header: {
            Text("账号")
        }
    }

    private func syncIfClean(force: Bool) {
        if force || draft == baseline {
            draft = app.displayName
            baseline = app.displayName
        }
    }

    private func saveNickname() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned = NicknameRules.cleaned(draft) else {
            errorText = trimmed.isEmpty ? "昵称不能为空" : "昵称最多 32 个字"
            return
        }
        if cleaned == app.displayName && app.nickname != nil {
            baseline = cleaned
            draft = cleaned
            errorText = nil
            return
        }
        saving = true
        defer { saving = false }
        do {
            let user = try await app.api.updateNickname(cleaned)
            app.applyUser(user)
            draft = app.displayName
            baseline = app.displayName
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

    private func restore() async {
        saving = true
        defer { saving = false }
        do {
            let user = try await app.api.deleteMyAvatar()
            app.applyUser(user)
            app.avatars.setUser(image: nil, updatedAt: nil)
            errorText = nil
        } catch {
            errorText = app.message(for: error)
        }
    }
}
