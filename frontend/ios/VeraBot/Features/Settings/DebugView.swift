import SwiftUI
import UIKit
import VeraBotCore

/// 调试：服务器地址、后端健康检查、版本与构建信息。由设置页导航栏右上角按钮 push 进入。
struct DebugView: View {
    @Environment(AppState.self) private var app
    @State private var health: HealthStatus?
    @State private var healthError: String?
    @State private var checking = false
    @State private var serverDraft = ""
    @State private var serverError: String?
    @FocusState private var editingServer: Bool
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some View {
        ThemedForm {
            Section {
                if app.token == nil {
                    TextField(AppConfig.defaultBaseURL, text: $serverDraft)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($editingServer).submitLabel(.done)
                        .onSubmit { saveServer() }
                    Button("保存服务器地址") { saveServer() }
                        .disabled(checking)
                    if let serverError { Text(serverError).font(.footnote).foregroundStyle(.red) }
                } else {
                    LabeledContent("服务器地址", value: app.baseURLString).textSelection(.enabled)
                }
            } header: {
                Text("连接配置")
            } footer: {
                Text(app.token == nil ? "模拟器可用本机地址；真机请填写电脑的局域网地址。" : "退出登录后可修改服务器地址。")
            }
            Section {
                LabeledContent("状态") {
                    if checking {
                        ProgressView()
                    } else if let health {
                        Text(health.ok ? "正常" : "异常")
                    } else if healthError != nil {
                        Text("无法连接")
                    } else {
                        Text("-")
                    }
                }
                if let model = health?.model {
                    LabeledContent("模型", value: model)
                }
                if let healthError {
                    Text(healthError).font(.footnote).foregroundStyle(.red)
                }
                Button("重新检查") { Task { await check() } }
                    .disabled(checking)
            } header: {
                Text("后端")
            } footer: {
                Text("健康检查：GET /api/health")
            }

            if let diagnostic = app.connectionDiagnostic {
                Section("最近的连接错误") {
                    Text(diagnostic).font(.footnote).textSelection(.enabled)
                }
            }

            Section("外观") {
                Picker("外观", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }

            Section("应用") {
                LabeledContent("版本", value: info("CFBundleShortVersionString"))
                LabeledContent("构建号", value: info("CFBundleVersion"))
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "-")
                LabeledContent("系统", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                #if DEBUG
                LabeledContent("构建配置", value: "Debug")
                #else
                LabeledContent("构建配置", value: "Release")
                #endif
            }

            Section("实验") {
                NavigationLink {
                    AvatarLabView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("头像实验室", systemImage: "face.smiling")
                }
                NavigationLink {
                    RobotAvatarLabView()
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label("新版头像实验室", systemImage: "eyes")
                }
            }
        }
        .navigationTitle("调试")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton { editingServer = false }
        .task { serverDraft = app.baseURLString; await check() }
    }

    private func info(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "-"
    }

    private func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            health = try await app.api.health()
            healthError = nil
        } catch {
            health = nil
            healthError = error.localizedDescription
        }
    }

    private func saveServer() {
        guard app.token == nil, !checking else { return }
        let value = serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
            serverError = "请输入有效的 http 或 https 服务器地址"
            return
        }
        app.baseURLString = value
        app.saveBaseURL()
        serverDraft = value
        serverError = nil
        app.connectionDiagnostic = nil
        editingServer = false
        Task { await check() }
    }
}
