import Foundation
import SwiftUI
import UIKit
import VeraBotCore
import VeraBotNetworking

/// 全局登录态与资料（昵称、头像）。首页和对话直接读这里，不在每个页面单独重拉。
/// MVP 使用 UserDefaults 存储 Token；生产环境应改用 Keychain。
@MainActor
@Observable
final class AppState {
    private enum Keys {
        static let token = "vb_token"
        static let username = "vb_username"
        static let nickname = "vb_nickname"
        static let hasAvatar = "vb_has_avatar"
        static let avatarUpdatedAt = "vb_avatar_updated_at"
        static let baseURL = "vb_base_url"
    }

    private(set) var token: String?
    private(set) var username: String?
    private(set) var nickname: String?
    private(set) var hasAvatar = false
    private(set) var avatarUpdatedAt: String?
    var baseURLString: String
    let avatars = AvatarStore()

    var displayName: String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return username ?? ""
    }

    init() {
        let d = UserDefaults.standard
        token = d.string(forKey: Keys.token)
        username = d.string(forKey: Keys.username)
        nickname = d.string(forKey: Keys.nickname)
        hasAvatar = d.bool(forKey: Keys.hasAvatar)
        avatarUpdatedAt = d.string(forKey: Keys.avatarUpdatedAt)
        baseURLString = d.string(forKey: Keys.baseURL) ?? AppConfig.defaultBaseURL
        if hasAvatar {
            avatars.loadCachedUser()
            if avatars.userImage != nil { avatars.noteUserStamp(avatarUpdatedAt) }
        }
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
        let previous = username
        token = auth.token
        UserDefaults.standard.set(auth.token, forKey: Keys.token)
        if previous != nil && previous != auth.user.username {
            avatars.clearAll()
        }
        applyUser(auth.user)
    }

    func applyUser(_ user: User) {
        username = user.username
        nickname = user.nickname
        hasAvatar = user.hasAvatar
        avatarUpdatedAt = user.avatarUpdatedAt
        let d = UserDefaults.standard
        d.set(user.username, forKey: Keys.username)
        if let nickname, !nickname.isEmpty {
            d.set(nickname, forKey: Keys.nickname)
        } else {
            d.removeObject(forKey: Keys.nickname)
        }
        d.set(user.hasAvatar, forKey: Keys.hasAvatar)
        if let avatarUpdatedAt {
            d.set(avatarUpdatedAt, forKey: Keys.avatarUpdatedAt)
        } else {
            d.removeObject(forKey: Keys.avatarUpdatedAt)
        }
    }

    /// 登录后或回到前台时拉一次资料和用户头像。各页面只读 AppState，不再各自请求。
    func refreshProfile() async {
        guard token != nil else { return }
        do {
            let user = try await api.me()
            guard token != nil else { return }
            applyUser(user)
            if user.hasAvatar {
                if avatars.needsUserDownload(updatedAt: user.avatarUpdatedAt) {
                    let data = try await api.myAvatarData()
                    guard token != nil, let image = UIImage(data: data) else { return }
                    avatars.setUser(image: image, updatedAt: user.avatarUpdatedAt)
                }
            } else {
                avatars.setUser(image: nil, updatedAt: nil)
            }
        } catch {
            if let e = error as? APIError, e.status == 401 {
                signOut()
            }
        }
    }

    func signOut() {
        token = nil
        username = nil
        nickname = nil
        hasAvatar = false
        avatarUpdatedAt = nil
        avatars.clearAll()
        let d = UserDefaults.standard
        d.removeObject(forKey: Keys.token)
        d.removeObject(forKey: Keys.username)
        d.removeObject(forKey: Keys.nickname)
        d.removeObject(forKey: Keys.hasAvatar)
        d.removeObject(forKey: Keys.avatarUpdatedAt)
    }

    /// 统一错误文案；401 时自动退出登录。
    func message(for error: Error) -> String {
        if let e = error as? APIError, e.status == 401 {
            signOut()
        }
        return error.localizedDescription
    }
}
