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
            Text("V")
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Color.brand,
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("VeraBot").font(.largeTitle.bold())
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
                    if loading { ProgressView() } else { Text(isRegister ? "注册并登录" : "登录") }
                }
                .frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
            .disabled(!canSubmit)

            Button(isRegister ? "已有账号？登录" : "还没有账号？注册") { isRegister.toggle() }
                .font(.footnote)

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
