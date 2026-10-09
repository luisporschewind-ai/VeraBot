import SwiftUI
import VeraBotCore
import VeraBotNetworking

/// Bot 小队欢迎页：默认邮箱登录，其他方式按需展开，开发信息集中到调试面板。
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
    @State private var showDebug = false
    @State private var showMethods = false
    @State private var connectionIssue: ConnectionIssue?
    @State private var retryCode = false
    @State private var hasRememberedLogin = false
    private let rememberedLogin = RememberedLoginStore()
    private enum Field: Hashable { case email, phone, password, code }
    @FocusState private var focus: Field?

    private var registering: Bool { isRegister && method.supportsRegister }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        guard !loading, !sendingCode else { return false }
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
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 26) {
                        welcome
                        VStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(registering ? "认识你的新伙伴" : "欢迎回来")
                                    .font(.title2.bold()).foregroundStyle(Color.brandText)
                                Text(registering ? "创建账号，组建你的助理团队。" : "登录后，和你的 Bot 继续聊聊。")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            fields
                            if let connectionIssue {
                                BotConnectionView(issue: connectionIssue, retrying: loading || sendingCode, compact: true) {
                                    focus = nil
                                    Task { if retryCode { await sendCode() } else { await submit() } }
                                }
                            } else if let errorText {
                                Text(errorText).font(.footnote).foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if let hint = infoText ?? hintText {
                                Text(hint).font(.footnote).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            submitButton
                            if method.supportsRegister {
                                Button(isRegister ? "已有账号？登录" : "还没有账号？注册") {
                                    isRegister.toggle(); clearFeedback()
                                    if isRegister { password = "" } else { restoreRememberedLogin() }
                                }
                                .font(.subheadline).disabled(loading || sendingCode)
                            }
                        }
                        .padding(22)
                        .background(Color.sectionFill.opacity(0.55), in: RoundedRectangle(cornerRadius: 28))
                        otherMethods
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .frame(maxWidth: 480)
                    .frame(minHeight: geometry.size.height, alignment: .center)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { focus = nil; showDebug = true } label: { Image(systemName: "ladybug") }
                        .accessibilityLabel("调试")
                        .disabled(loading || sendingCode)
                }
            }
            .sheet(isPresented: $showDebug) {
                NavigationStack {
                    DebugView().toolbar { ToolbarItem(placement: .topBarLeading) {
                        DismissToolbarButton(kind: .close) { showDebug = false }
                    } }
                }
            }
            .keyboardDoneButton { focus = nil }
            .onAppear { restoreRememberedLogin() }
            .onChange(of: app.baseURLString) {
                clearFeedback(); restoreRememberedLogin()
            }
            .task(id: cooldown) {
                guard cooldown > 0 else { return }
                do {
                    try await Task.sleep(for: .seconds(1))
                    if cooldown > 0 { cooldown -= 1 }
                } catch { /* No countdown ticks after leaving the page. */ }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            BotWelcomeGroup(size: 96)
            VStack(spacing: 6) {
                Text("Vera Bot").font(.largeTitle.bold()).foregroundStyle(Color.brandText)
                Text("你的私人 AI 助理团队").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var fields: some View {
        VStack(spacing: 12) {
            switch method {
            case .emailPassword:
                emailField
                passwordField
            case .phonePassword:
                TextField("手机号", text: $phone)
                    .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    .focused($focus, equals: .phone).themedFieldBackground()
                passwordField
            case .emailCode:
                emailField
                HStack(spacing: 10) {
                    TextField("6 位验证码", text: $code)
                        .textContentType(.oneTimeCode).keyboardType(.numberPad)
                        .focused($focus, equals: .code).themedFieldBackground()
                    Button { Task { await sendCode() } } label: {
                        if sendingCode { ProgressView() }
                        else { Text(cooldown > 0 ? "\(cooldown) 秒" : "获取验证码") }
                    }
                    .buttonStyle(.bordered).controlSize(.large).monospacedDigit()
                    .disabled(loading || sendingCode || cooldown > 0 || AuthInputRules.normalizedEmail(email) == nil)
                }
            }
        }
        .disabled(loading || sendingCode)
    }

    private var submitButton: some View {
        Button {
            focus = nil
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if loading { ProgressView().tint(.white) }
                Text(loading ? (registering ? "正在注册…" : "正在登录…") : (registering ? "注册并登录" : "登录"))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .prominentButtonStyle().controlSize(.large)
        .disabled((!canSubmit && !loading) || sendingCode)
        .allowsHitTesting(!loading)
    }

    private var otherMethods: some View {
        VStack(spacing: 12) {
            Button { showMethods.toggle() } label: {
                HStack(spacing: 6) {
                    Text(showMethods ? "收起登录方式" : "其他登录方式")
                    Image(systemName: showMethods ? "chevron.up" : "chevron.down")
                }.font(.footnote)
            }
            if hasRememberedLogin {
                Button("忘记已保存的登录信息") {
                    if rememberedLogin.remove(server: app.baseURLString) {
                        hasRememberedLogin = false
                        email = ""; phone = ""; password = ""
                        clearFeedback()
                    } else {
                        errorText = "暂时无法清除登录信息，请重试"
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if showMethods {
                Picker("登录方式", selection: $method) {
                    ForEach(AuthMethod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: method) {
                    clearFeedback(); focus = nil
                    let saved = rememberedLogin.load(server: app.baseURLString)
                    password = saved?.isPhone == (method == .phonePassword) && !registering ? saved?.password ?? "" : ""
                }
            }
        }
        .disabled(loading || sendingCode)
    }

    private func restoreRememberedLogin() {
        let saved = rememberedLogin.load(server: app.baseURLString)
        hasRememberedLogin = saved != nil
        email = ""; phone = ""; password = ""; code = ""
        isRegister = false
        guard let saved else { method = .emailPassword; return }
        method = saved.isPhone ? .phonePassword : .emailPassword
        if saved.isPhone { phone = saved.identifier } else { email = saved.identifier }
        password = saved.password
    }

    private func clearFeedback() {
        errorText = nil; infoText = nil; connectionIssue = nil
    }

    private func showFailure(_ error: Error) {
        guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        connectionIssue = ConnectionIssue.classify(error)
        if connectionIssue != nil {
            app.connectionDiagnostic = error.localizedDescription
            errorText = nil
        } else {
            errorText = app.message(for: error)
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
        guard let addr = AuthInputRules.normalizedEmail(email), !sendingCode, !loading, cooldown == 0 else { return }
        let generation = app.sessionGeneration
        let endpoint = app.baseURLString
        retryCode = true
        sendingCode = true
        errorText = nil
        defer { sendingCode = false }
        app.saveBaseURL()
        do {
            let sent = try await app.api.sendEmailCode(email: addr)
            guard !Task.isCancelled, app.isCurrentSession(generation), app.baseURLString == endpoint else { return }
            connectionIssue = nil
            app.connectionDiagnostic = nil
            cooldown = sent.retryAfter ?? 60
            infoText = "验证码已发送，\((sent.expiresIn ?? 600) / 60) 分钟内有效"
            focus = .code
        } catch {
            guard app.isCurrentSession(generation), app.baseURLString == endpoint else { return }
            showFailure(error)
        }
    }

    private func submit() async {
        guard !loading, canSubmit else { return }
        let generation = app.sessionGeneration
        let endpoint = app.baseURLString
        retryCode = false
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
            guard !Task.isCancelled, app.isCurrentSession(generation), app.baseURLString == endpoint else { return }
            connectionIssue = nil
            app.connectionDiagnostic = nil
            let identifier = method == .phonePassword ? (AuthInputRules.normalizedPhone(phone) ?? phone) : trimmedEmail
            rememberedLogin.save(.init(identifier: identifier,
                                        password: method == .emailCode ? "" : password,
                                        isPhone: method == .phonePassword), server: endpoint)
            app.signIn(auth)
        } catch {
            guard app.isCurrentSession(generation), app.baseURLString == endpoint else { return }
            showFailure(error)
        }
    }
}
