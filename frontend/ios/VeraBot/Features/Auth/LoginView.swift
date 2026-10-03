import SwiftUI
import VeraBotCore

struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var username = ""
    @State private var password = ""
    @State private var isRegister = false
    @State private var loading = false
    @State private var errorText: String?
    @State private var showServer = false
    private enum Field: Hashable { case username, password, server }
    @FocusState private var focus: Field?
    private var canSubmit: Bool { !loading && username.count >= 3 && password.count >= 6 }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 18) {
            Spacer()
            // 与主屏图标一致：AppLogo 由 AppIcon 1024 图生成，含深色外观变体
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .accessibilityHidden(true)
            Text("Vera Bot").font(.largeTitle.bold())
            Text("你的私人 AI 助理团队").foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("用户名", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .themedFieldBackground()
                SecureField("密码（至少 6 位）", text: $password)
                    .textContentType(isRegister ? .newPassword : .password)
                    .focused($focus, equals: .password)
                    .submitLabel(.done)
                    .onSubmit {
                        focus = nil
                        if canSubmit { Task { await submit() } }
                    }
                    .themedFieldBackground()
            }
            .padding(.top, 8)

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }

            Button {
                focus = nil
                Task { await submit() }
            } label: {
                Group {
                    if loading {
                        // 白色转圈 + 文案：按钮保持品牌色，不会因禁用变灰导致转圈看不清
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text(isRegister ? "正在注册…" : "正在登录…")
                        }
                    } else {
                        Text(isRegister ? "注册并登录" : "登录")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
            .disabled(!canSubmit && !loading)   // 加载中不置灰；由 allowsHitTesting + submit 守卫防重复提交
            .allowsHitTesting(!loading)

            Button(isRegister ? "已有账号？登录" : "还没有账号？注册") { isRegister.toggle() }
                .font(.footnote)
                .disabled(loading)

            Spacer()
            DisclosureGroup("服务器地址", isExpanded: $showServer) {
                TextField(AppConfig.defaultBaseURL, text: $app.baseURLString)
                    .themedFieldBackground()
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .server)
                    .submitLabel(.done)
                    .onSubmit { app.saveBaseURL(); focus = nil }
            }
            .font(.footnote)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .contentShape(Rectangle())
        .onTapGesture { focus = nil }            // 点空白处收起键盘
        .keyboardDoneButton { focus = nil }      // 键盘工具栏「完成」
    }

    private func submit() async {
        guard !loading else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        app.saveBaseURL()
        let creds = Credentials(username: username.trimmingCharacters(in: .whitespaces), password: password)
        do {
            let auth = isRegister ? try await app.api.register(creds) : try await app.api.login(creds)
            app.signIn(auth)
        } catch {
            errorText = app.message(for: error)
        }
    }
}
