import Foundation
import SwiftUI
import VeraBotCore
import VeraBotNetworking

/// 全局登录态（MVP 使用 UserDefaults 存储 Token；生产环境应改用 Keychain）。
@MainActor
@Observable
final class AppState {
    private enum Keys {
        static let token = "vb_token"
        static let username = "vb_username"
        static let baseURL = "vb_base_url"
    }

    private(set) var token: String?
    private(set) var username: String?
    var baseURLString: String

    init() {
        let d = UserDefaults.standard
        token = d.string(forKey: Keys.token)
        username = d.string(forKey: Keys.username)
        baseURLString = d.string(forKey: Keys.baseURL) ?? AppConfig.defaultBaseURL
    }

    /// 当前后端 API（依赖协议 VeraBotAPI，实现为 VeraBotNetworking.APIClient）
    var api: any VeraBotAPI {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmed) ?? URL(string: AppConfig.defaultBaseURL)!
        return APIClient(baseURL: url, token: token)
    }

    func saveBaseURL() {
        UserDefaults.standard.set(baseURLString, forKey: Keys.baseURL)
    }

    func signIn(_ auth: AuthResponse) {
        token = auth.token
        username = auth.user.username
        UserDefaults.standard.set(auth.token, forKey: Keys.token)
        UserDefaults.standard.set(auth.user.username, forKey: Keys.username)
    }

    func signOut() {
        token = nil
        username = nil
        UserDefaults.standard.removeObject(forKey: Keys.token)
        UserDefaults.standard.removeObject(forKey: Keys.username)
    }

    /// 统一错误文案；401 时自动退出登录。
    func message(for error: Error) -> String {
        if let e = error as? APIError, e.status == 401 {
            signOut()
        }
        return error.localizedDescription
    }
}
