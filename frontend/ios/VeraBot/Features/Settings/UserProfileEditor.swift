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
    @State private var verifyCode = ""
    @State private var enteringCode = false
    @State private var sendingVerify = false
    @State private var infoText: String?

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
                            // 邮箱 / 手机号账号显示邮箱或手机号；老的用户名账号（demo）显示「用户名 xxx」
                            Text(app.accountLabel)
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
            if app.needsEmailVerification {
                // 未验证邮箱也能正常使用，这里只提醒（docs/design/AUTH_REFACTOR.md §决策）
                HStack {
                    Label("邮箱未验证", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    Spacer()
                    if sendingVerify { ProgressView() }
                    Button("验证") { Task { await sendVerification() } }
                        .buttonStyle(.borderless)
                        .disabled(sendingVerify)
                }
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            } else if let infoText {
                Text(infoText).font(.footnote).foregroundStyle(.secondary)
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
        .alert("验证邮箱", isPresented: $enteringCode) {
            TextField("6 位验证码", text: $verifyCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            Button("取消", role: .cancel) {}
            Button("验证") { Task { await verify() } }
        } message: {
            Text("验证码已发送到 \(app.email ?? "")，10 分钟内有效")
        }
    }

    private func sendVerification() async {
        sendingVerify = true
        defer { sendingVerify = false }
        do {
            _ = try await app.api.sendVerificationEmail()
            errorText = nil
            verifyCode = ""
            enteringCode = true
        } catch let e as APIError where e.code == "code_cooldown" {
            // 刚注册 / 刚发过：上一封里的验证码仍然有效，直接让用户输入
            errorText = nil
            verifyCode = ""
            enteringCode = true
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func verify() async {
        let trimmed = verifyCode.trimmingCharacters(in: .whitespaces)
        guard AuthInputRules.isValidCode(trimmed) else {
            errorText = "请输入 6 位数字验证码"
            return
        }
        do {
            let user = try await app.api.verifyEmail(code: trimmed)
            app.applyUser(user)
            errorText = nil
            infoText = "邮箱已验证"
        } catch {
            errorText = app.message(for: error)
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
