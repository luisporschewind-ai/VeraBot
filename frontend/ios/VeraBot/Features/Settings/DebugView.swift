import SwiftUI
import UIKit
import VeraBotCore

/// 调试：服务器地址、后端健康检查、版本与构建信息。由设置页导航栏右上角按钮 push 进入。
struct DebugView: View {
    @Environment(AppState.self) private var app
    @State private var health: HealthStatus?
    @State private var healthError: String?
    @State private var checking = false

    var body: some View {
        ThemedForm {
            Section {
                LabeledContent("服务器地址", value: app.baseURLString)
                    .textSelection(.enabled)
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
                Text("服务器地址在登录页「服务器地址」中修改（需先退出登录）。健康检查：GET /api/health")
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
            }
        }
        .navigationTitle("调试")
        .navigationBarTitleDisplayMode(.inline)
        .task { await check() }
    }

    private func info(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "-"
    }

    private func check() async {
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
}
