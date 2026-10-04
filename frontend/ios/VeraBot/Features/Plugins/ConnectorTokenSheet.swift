import SwiftUI
import VeraBotCore

/// 连接需令牌的插件（GitHub / Linear）：系统 Form + SecureField。令牌先暂存 Keychain，再上传一次；
/// 后端校验后加密保存，App 不再保留（成功后删除暂存）。上传只能经本机 127.0.0.1 或 HTTPS（后端强制）。
struct ConnectorTokenSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let plugin: Plugin
    let onConnected: (Plugin) -> Void

    @State private var token = ""
    @State private var busy = false
    @State private var errorText: String?

    private var keychainAccount: String { ConnectorKeychain.account(userID: app.userID, pluginID: plugin.pluginId) }

    var body: some View {
        Form {
            Section {
                SecureField("粘贴令牌", text: $token)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .privacySensitive()
            } footer: {
                Text(plugin.credentialHelp ?? "令牌加密保存在 VeraBot 服务器，不会发给 DeepSeek，也不会返回给 App。")
            }
            if let raw = plugin.credentialHelpURL, let url = URL(string: raw) {
                Section {
                    Link("在 \(plugin.publisher.isEmpty ? plugin.name : plugin.publisher) 创建令牌", destination: url)
                }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
        }
        .navigationTitle("连接 \(plugin.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if busy {
                    ProgressView()
                } else {
                    Button("连接") { Task { await connect() } }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear {
            if token.isEmpty, let staged = ConnectorKeychain.load(account: keychainAccount) { token = staged }
        }
    }

    private func connect() async {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        defer { busy = false }
        ConnectorKeychain.stage(value, account: keychainAccount)
        do {
            let updated = try await app.api.setPluginCredential(id: plugin.pluginId, token: value)
            ConnectorKeychain.remove(account: keychainAccount)   // D3：成功后不保留副本
            token = ""
            onConnected(updated)
            dismiss()
        } catch {
            errorText = app.message(for: error)   // 失败保留暂存，可重试；取消不删除
        }
    }
}
