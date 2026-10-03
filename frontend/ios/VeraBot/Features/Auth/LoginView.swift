import SwiftUI
import VeraBotCore

/// 登录 / 注册（账号 v9）：分段选择 邮箱+密码 / 邮箱+验证码 / 手机号+密码。系统默认控件样式。
/// 邮箱框也接受老的用户名（demo 开发账号），用户名不在界面上单独出现。见 docs/design/AUTH_REFACTOR.md。
struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var method: AuthMethod = .emailPassword
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var code = ""
    @State private var isRegister = false
    @State private var loading = false
    @State private var sendingCode = false
    @State private var cooldown = 0
    @State private var errorText: String?
    @State private var infoText: String?
    @State private var showServer = false
    private enum Field: Hashable { case email, phone, password, code, server }
    @FocusState private var focus: Field?

    private var registering: Bool { isRegister && method.supportsRegister }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        guard !loading else { return false }
        switch method {
        case .emailPassword:
            if registering { return AuthInputRules.normalizedEmail(email) != nil && password.count >= AuthInputRules.passwordMin }
            return trimmedEmail.count >= 3 && !password.isEmpty
        case .phonePassword:
            guard AuthInputRules.normalizedPhone(phone) != nil else { return false }
            return registering ? password.count >= AuthInputRules.passwordMin : !password.isEmpty
        case .emailCode:
            return AuthInputRules.normalizedEmail(email) != nil && AuthInputRules.isValidCode(code)
        }
    }

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

            Picker("登录方式", selection: $method) {
                ForEach(AuthMethod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(loading)
            .padding(.top, 4)
            .onChange(of: method) { errorText = nil; infoText = nil }

            VStack(spacing: 12) {
                switch method {
                case .emailPassword:
                    emailField
                    passwordField
                case .phonePassword:
                    TextField("手机号", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focus, equals: .phone)
                        .themedFieldBackground()
                    passwordField
                case .emailCode:
                    emailField
                    HStack(spacing: 10) {
                        TextField("6 位验证码", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .code)
                            .themedFieldBackground()
                        Button {
                            Task { await sendCode() }
                        } label: {
                            if sendingCode { ProgressView() } else { Text(cooldown > 0 ? "\(cooldown) 秒" : "获取验证码") }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .monospacedDigit()
                        .disabled(sendingCode || cooldown > 0 || AuthInputRules.normalizedEmail(email) == nil)
                    }
                }
            }

            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            } else if let hint = infoText ?? hintText {
                Text(hint).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                            Text(registering ? "正在注册…" : "正在登录…")
                        }
                    } else {
                        Text(registering ? "注册并登录" : "登录")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
            .disabled(!canSubmit && !loading)   // 加载中不置灰；由 allowsHitTesting + submit 守卫防重复提交
            .allowsHitTesting(!loading)

            if method.supportsRegister {
                Button(isRegister ? "已有账号？登录" : "还没有账号？注册") { isRegister.toggle(); errorText = nil }
                    .font(.footnote)
                    .disabled(loading)
            }

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
        .task(id: cooldown) {
            guard cooldown > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            if cooldown > 0 { cooldown -= 1 }
        }
    }

    private var hintText: String? {
        switch method {
        case .emailCode: "新邮箱首次登录会自动创建账号"
        case .emailPassword where registering: "注册后会发一封验证邮件；未验证也能正常使用"
        case .phonePassword where registering: "密码至少 8 位；暂不发送短信验证"
        default: nil
        }
    }

    private var emailField: some View {
        TextField("邮箱", text: $email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: .email)
            .submitLabel(.next)
            .onSubmit { focus = method == .emailCode ? .code : .password }
            .themedFieldBackground()
    }

    private var passwordField: some View {
        SecureField(registering ? "密码（至少 8 位）" : "密码", text: $password)
            .textContentType(registering ? .newPassword : .password)
            .focused($focus, equals: .password)
            .submitLabel(.done)
            .onSubmit {
                focus = nil
                if canSubmit { Task { await submit() } }
            }
            .themedFieldBackground()
    }

    private func sendCode() async {
        guard let addr = AuthInputRules.normalizedEmail(email), !sendingCode else { return }
        sendingCode = true
        errorText = nil
        defer { sendingCode = false }
        app.saveBaseURL()
        do {
            let sent = try await app.api.sendEmailCode(email: addr)
            cooldown = sent.retryAfter ?? 60
            infoText = "验证码已发送，\((sent.expiresIn ?? 600) / 60) 分钟内有效"
            focus = .code
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func submit() async {
        guard !loading, canSubmit else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        app.saveBaseURL()
        do {
            let auth: AuthResponse
            switch method {
            case .emailPassword:
                if registering {
                    auth = try await app.api.register(RegisterRequest(email: AuthInputRules.normalizedEmail(email), password: password))
                } else {
                    auth = try await app.api.login(LoginRequest(identifier: trimmedEmail, password: password))
                }
            case .phonePassword:
                let normalized = AuthInputRules.normalizedPhone(phone) ?? phone
                auth = registering
                    ? try await app.api.register(RegisterRequest(phone: normalized, password: password))
                    : try await app.api.login(LoginRequest(identifier: normalized, password: password))
            case .emailCode:
                auth = try await app.api.loginWithEmailCode(email: AuthInputRules.normalizedEmail(email) ?? trimmedEmail,
                                                            code: code.trimmingCharacters(in: .whitespaces))
            }
            app.signIn(auth)
        } catch {
            errorText = app.message(for: error)
        }
    }
}
