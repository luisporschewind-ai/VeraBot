import Foundation
import SwiftUI
import UIKit
import VeraBotCore
import VeraBotNetworking

/// 全局登录态与资料（昵称、头像、邮箱 / 手机号）。首页和对话直接读这里，不在每个页面单独重拉。
/// 令牌（访问 7 天 + 刷新 60 天）存 Keychain，由共享的 AuthSession 持有：任何请求 401 时透明刷新一次；
/// 刷新令牌也失效时请求仍返回 401，统一走 signOut。旧版存在 UserDefaults 的 vb_token 首次启动时迁到 Keychain。
///
/// 账号隔离：API 走无缓存的 `APITransport.session`；退出、登录（换账号）、以及升级后首次启动都会清掉
/// URLCache 的磁盘缓存（`HTTPCachePurge`）。异步拉资料 / 头像前记下 `sessionGeneration`，回来后
/// `isCurrentSession` 不成立（期间退出或换了账号）就丢掉结果，不会把上一个账号的数据写到新账号上。
@MainActor
@Observable
final class AppState {
    private enum Keys {
        static let legacyToken = "vb_token"   // v0.1 存在 UserDefaults，仅用于迁移
        static let email = "vb_email"
        static let emailVerified = "vb_email_verified"
        static let phone = "vb_phone"
        static let serverDisplayName = "vb_display_name"
        static let username = "vb_username"
        static let nickname = "vb_nickname"
        static let hasAvatar = "vb_has_avatar"
        static let avatarUpdatedAt = "vb_avatar_updated_at"
        static let baseURL = "vb_base_url"
        static let userID = "vb_user_id"
    }

    /// 是否已登录（非 nil 即已登录）；实际请求用 authSession 里的最新访问令牌。
    private(set) var token: String?
    private(set) var email: String?
    private(set) var emailVerified = false
    private(set) var phone: String?
    private var serverDisplayName: String?
    let authSession: AuthSession
    private(set) var username: String?
    private(set) var nickname: String?
    private(set) var hasAvatar = false
    private(set) var avatarUpdatedAt: String?
    private(set) var userID: Int?
    var unreadCount = 0
    var selectedTab = 0
    var pendingLink: DeepLink?
    var missingNotice: String?
    var showNotificationSettings = false
    var baseURLString: String
    let avatars = AvatarStore()

    var displayName: String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        if let serverDisplayName, !serverDisplayName.isEmpty { return serverDisplayName }
        return username ?? ""
    }

    /// 设置页名字下面那行：邮箱 / 手机号；老的用户名账号（demo）显示「用户名 xxx」。
    var accountLabel: String {
        User(id: 0, username: username ?? "", email: email, emailVerified: emailVerified, phone: phone).accountLabel
    }

    var needsEmailVerification: Bool { (email?.isEmpty == false) && !emailVerified }

    init() {
        let d = UserDefaults.standard
        // 旧版本把 API 响应（含令牌、对话、记忆）写进了 Caches/<bundle id>/Cache.db：升级后首次启动清一次。
        HTTPCachePurge.runOnce(defaults: d) { HTTPCachePurge.purgeAppCaches() }
        // 兜底：即使以后有代码误用 URLSession.shared，也不再落盘。
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil)
        var stored = KeychainStore.load()
        if stored == nil, let legacy = d.string(forKey: Keys.legacyToken) {
            stored = AuthTokens(access: legacy, refresh: nil)   // 旧令牌没有刷新令牌，过期后重新登录
            KeychainStore.save(stored)
        }
        d.removeObject(forKey: Keys.legacyToken)
        authSession = AuthSession(tokens: stored) { tokens, _ in KeychainStore.save(tokens) }
        token = stored?.access
        email = d.string(forKey: Keys.email)
        emailVerified = d.bool(forKey: Keys.emailVerified)
        phone = d.string(forKey: Keys.phone)
        serverDisplayName = d.string(forKey: Keys.serverDisplayName)
        username = d.string(forKey: Keys.username)
        nickname = d.string(forKey: Keys.nickname)
        hasAvatar = d.bool(forKey: Keys.hasAvatar)
        avatarUpdatedAt = d.string(forKey: Keys.avatarUpdatedAt)
        let storedUser = d.integer(forKey: Keys.userID)
        userID = storedUser == 0 ? nil : storedUser
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
        return APIClient(baseURL: url, session: authSession)
    }

    /// 当前登录会话代号（登录 / 退出时变化，透明刷新不变）。
    var sessionGeneration: UInt64 { authSession.generation }

    /// 异步任务回来时判断：还是同一次登录（没退出、没换账号）。
    func isCurrentSession(_ generation: UInt64) -> Bool { authSession.isCurrent(generation) }

    func saveBaseURL() {
        UserDefaults.standard.set(baseURLString, forKey: Keys.baseURL)
    }

    func signIn(_ auth: AuthResponse) {
        let previous = username
        HTTPCachePurge.purgeAppCaches()
        token = auth.token
        authSession.set(AuthTokens(access: auth.token, refresh: auth.refreshToken))
        if previous != nil && previous != auth.user.username {
            avatars.clearAll()
            AttachmentImageStore.shared.clearAll()
        }
        applyUser(auth.user)
    }

    func applyUser(_ user: User) {
        username = user.username
        nickname = user.nickname
        hasAvatar = user.hasAvatar
        avatarUpdatedAt = user.avatarUpdatedAt
        email = user.email
        emailVerified = user.emailVerified
        phone = user.phone
        serverDisplayName = user.displayName
        let d = UserDefaults.standard
        userID = user.id
        d.set(user.id, forKey: Keys.userID)
        d.set(user.username, forKey: Keys.username)
        d.set(user.email, forKey: Keys.email)
        d.set(user.emailVerified, forKey: Keys.emailVerified)
        d.set(user.phone, forKey: Keys.phone)
        d.set(user.displayName, forKey: Keys.serverDisplayName)
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
        let generation = sessionGeneration
        do {
            let user = try await api.me()
            guard isCurrentSession(generation) else { return }   // 期间退出 / 换了账号：丢掉
            applyUser(user)
            if user.hasAvatar {
                if avatars.needsUserDownload(updatedAt: user.avatarUpdatedAt) {
                    let data = try await api.myAvatarData()
                    guard isCurrentSession(generation), let image = UIImage(data: data) else { return }
                    avatars.setUser(image: image, updatedAt: user.avatarUpdatedAt)
                }
            } else {
                avatars.setUser(image: nil, updatedAt: nil)
            }
        } catch {
            // 只有当前这次登录的 401 才退出；上一个账号的旧请求失败不能把新账号踢下线
            if let e = error as? APIError, e.status == 401, isCurrentSession(generation) {
                signOut()
            }
        }
    }

    func signOut() {
        let refresh = authSession.tokens?.refresh
        let device = DeviceIdentity.current()
        let uid = userID
        let api = self.api
        if let uid { ReminderOutboxStore.remove(userID: uid) }
        NotificationCoordinator.shared.clearAll()
        DeviceIdentity.rotate()
        // 先注销设备，再吊销刷新令牌。失败不影响本地退出。
        Task.detached {
            _ = try? await api.deleteDevice(device)
            if let refresh { _ = try? await api.logout(refreshToken: refresh) }
        }
        authSession.set(nil)
        token = nil
        email = nil
        emailVerified = false
        phone = nil
        serverDisplayName = nil
        username = nil
        nickname = nil
        hasAvatar = false
        avatarUpdatedAt = nil
        avatars.clearAll()
        AttachmentImageStore.shared.clearAll()   // 对话图片内存缓存 + 全屏预览临时文件
        HTTPCachePurge.purgeAppCaches()
        let d = UserDefaults.standard
        for key in [Keys.email, Keys.emailVerified, Keys.phone, Keys.serverDisplayName] { d.removeObject(forKey: key) }
        d.removeObject(forKey: Keys.username)
        d.removeObject(forKey: Keys.nickname)
        d.removeObject(forKey: Keys.hasAvatar)
        d.removeObject(forKey: Keys.avatarUpdatedAt)
        userID = nil
        unreadCount = 0
        pendingLink = nil
        d.removeObject(forKey: Keys.userID)
    }

    /// 统一错误文案；401 时自动退出登录。
    func message(for error: Error) -> String {
        if let e = error as? APIError, e.status == 401 {
            signOut()
        }
        return error.localizedDescription
    }
}
