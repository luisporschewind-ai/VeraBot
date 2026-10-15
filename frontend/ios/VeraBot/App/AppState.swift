import Foundation
import SwiftUI
import UIKit
import CryptoKit
import VeraBotCore
import VeraBotNetworking
import VeraBotPersistence
import VeraBotData

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
    var primaryBotID: Int?
    var primarySettings: PrimaryBotSettings?
    private(set) var primaryBotRepository: PrimaryBotRepository?
    private(set) var ownedTaskRepository: OwnedTaskRepository?
    private(set) var scheduledTaskRepository: ScheduledTaskRepository?
    var conversationActivities: [String: ConversationActivity] = [:]
    var activitySuccessIDs: Set<String> = []
    private var activitySuccessSerial: [String: Int] = [:]
    var activityNeedsSync = true
    var activityRepository: ConversationActivityRepository?
    private var activityObservation: Task<Void, Never>?
    private var activityCursor = 0
    private var appIsForeground = true
    @ObservationIgnored var reminderRequests = NotificationRequestGate()
    func isCurrentReminderRequest(_ token: NotificationRequestToken) -> Bool {
        reminderRequests.isCurrent(token, session: sessionGeneration)
    }
    @ObservationIgnored lazy var notificationEvents = NotificationEventSync(app: self)
    var unreadCount = 0
    var selectedTab = 0
    var pendingLink: DeepLink?
    var missingNotice: String?
    var showNotificationSettings = false
    var baseURLString: String
    /// Last transport failure for the debug page; never rendered in product copy.
    var connectionDiagnostic: String?
    let avatars = AvatarStore()
    private(set) var conversationRepository: ConversationRepository?
    private var conversationDatabaseURL: URL?
    private var conversationDatabase: LocalDatabase?

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
        activatePersistenceScope()
    }

    /// 当前后端 API（依赖协议 VeraBotAPI，实现为 VeraBotNetworking.APIClient）
    var api: any VeraBotAPI { groupAPI }

    var groupAPI: APIClient {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmed) ?? URL(string: AppConfig.defaultBaseURL)!
        return APIClient(baseURL: url, session: authSession)
    }

    /// 当前登录会话代号（登录 / 退出时变化，透明刷新不变）。
    var sessionGeneration: UInt64 { authSession.generation }

    /// 异步任务回来时判断：还是同一次登录（没退出、没换账号）。
    func isCurrentSession(_ generation: UInt64) -> Bool { authSession.isCurrent(generation) }

    /// 登录前没有令牌；只判断请求期间会话是否变化，不要求已经登录。
    func isCurrentAuthAttempt(_ generation: UInt64) -> Bool { authSession.isCurrentAuthAttempt(generation) }

    func saveBaseURL() {
        _ = reminderRequests.begin(session: sessionGeneration)
        notificationEvents.invalidate()
        NotificationCoordinator.shared.clearAll()
        invalidatePersistenceScope()
        UserDefaults.standard.set(baseURLString, forKey: Keys.baseURL)
        activatePersistenceScope()
    }

    func signIn(_ auth: AuthResponse) {
        let previous = username
        invalidatePersistenceScope()
        HTTPCachePurge.purgeAppCaches()
        token = auth.token
        authSession.set(AuthTokens(access: auth.token, refresh: auth.refreshToken))
        if previous != nil && previous != auth.user.username {
            avatars.clearAll()
            AttachmentImageStore.shared.clearAll()
        }
        applyUser(auth.user)
        activatePersistenceScope()
    }

    func applyUser(_ user: User) {
        primaryBotID = user.primaryBotID
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
            await refreshPrimarySettings()
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

    func refreshPrimarySettings() async {
        let g=sessionGeneration
        if let repo=primaryBotRepository {
            if let cached=try? await repo.cached(),isCurrentSession(g){primarySettings=cached;primaryBotID=cached.primaryBotID}
            try? await repo.load()
            guard isCurrentSession(g) else{return}
            primarySettings=repo.settings;primaryBotID=repo.settings?.primaryBotID
        }
    }
    func setPrimaryBot(_ id:Int?) async {
        await refreshPrimarySettings()
        guard let s=primarySettings,let repo=primaryBotRepository else{return}
        let g=sessionGeneration
        do {try await repo.update(botID:id,activeEnabled:id != nil && s.activeEnabled,expectedVersion:s.version);guard isCurrentSession(g) else{return};primarySettings=repo.settings;primaryBotID=repo.settings?.primaryBotID}
        catch {guard isCurrentSession(g) else{return};primarySettings=repo.settings;primaryBotID=repo.settings?.primaryBotID;missingNotice=message(for:error)}
    }
    func setActiveTasks(_ enabled:Bool) async {
        await refreshPrimarySettings()
        guard let s=primarySettings,let repo=primaryBotRepository else{return}
        let g=sessionGeneration
        do {try await repo.update(botID:s.primaryBotID,activeEnabled:enabled,expectedVersion:s.version);guard isCurrentSession(g) else{return};primarySettings=repo.settings}
        catch {if isCurrentSession(g){missingNotice=message(for:error)}}
    }

    func signOut() {
        notificationEvents.invalidate()
        let oldRepository = conversationRepository
        let oldDatabaseURL = conversationDatabaseURL
        primaryBotRepository?.close(); ownedTaskRepository?.close(); scheduledTaskRepository?.close()
        primaryBotRepository = nil; ownedTaskRepository = nil; scheduledTaskRepository = nil
        primaryBotID = nil; primarySettings = nil
        conversationRepository = nil
        conversationDatabaseURL = nil
        // Close before yielding, so queued work cannot reopen this account's old connection.
        conversationDatabase?.close()
        conversationDatabase = nil
        if let oldRepository { Task { await oldRepository.invalidate() } }
        if let oldDatabaseURL {
            let directory = oldDatabaseURL.deletingLastPathComponent()
            let retired = directory.deletingLastPathComponent()
                .appendingPathComponent(".retired-\(UUID().uuidString)", isDirectory: true)
            if FileManager.default.fileExists(atPath: directory.path) {
                do {
                    // A same-account sign-in may recreate directory immediately. Cleanup owns only retired.
                    try FileManager.default.moveItem(at: directory, to: retired)
                    Task.detached { try? FileManager.default.removeItem(at: retired) }
                } catch {
                    // Never defer deletion of the reusable account path when isolation fails.
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }
        let refresh = authSession.tokens?.refresh
        let device = DeviceIdentity.current()
        let uid = userID
        let api = self.api
        if let uid { ReminderOutboxStore.remove(userID: uid, server: baseURLString) }
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

    var libraryRepository: LibraryRepository?
    var libraryDownloads: LibraryDownloadCoordinator?

    func refreshLibrary() async {
        guard let repository=libraryRepository else { return }
        if let cached=try? await repository.cachedItems() { libraryDownloads?.updateCatalog(cached,complete:false) }
        do {
            try await repository.synchronize()
            let list=try await repository.cachedItems()
            libraryDownloads?.updateCatalog(list,complete:true)
        } catch { /* Keep the offline catalog and originals. Pages display refresh failures. */ }
    }

    private func activatePersistenceScope() {
        guard token != nil, let userID else { conversationRepository = nil; return }
        let endpoint = (URL(string: baseURLString)?.absoluteString ?? baseURLString)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let scope = Data("\(endpoint)|\(userID)".utf8)
        let name = SHA256.hash(data: scope).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VeraBot/Accounts/\(name)", isDirectory: true)
        let url = root.appendingPathComponent("conversation.sqlite")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = root
        try? protectedURL.setResourceValues(values)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: root.path)
        let generation = authSession.generation
        let session = authSession
        let database = LocalDatabase(url: url)
        conversationDatabase = database
        let libraryStore=LibraryStore(database:database)
        let libraryAPI=groupAPI
        libraryRepository=LibraryRepository(store:libraryStore,api:libraryAPI,sessionIsCurrent:{session.isCurrent(generation)})
        libraryDownloads=LibraryDownloadCoordinator(root:root,scope:name,store:libraryStore,api:libraryAPI,sessionIsCurrent:{session.isCurrent(generation)})
        activityRepository = ConversationActivityRepository(database: database, sessionIsCurrent: { session.isCurrent(generation) })
        Task {
            try? database.open()
        }
        let store = ConversationStore(database: database)
        let api = groupAPI
        primaryBotRepository = PrimaryBotRepository(api:api,store:store)
        Task {await refreshPrimarySettings()}
        ownedTaskRepository = OwnedTaskRepository(api:api,store:store)
        scheduledTaskRepository = ScheduledTaskRepository(api:api,store:store)
        conversationRepository = ConversationRepository(store: store, api: api, groupAPI: api,
                                                        sessionIsCurrent: { session.isCurrent(generation) })
        conversationDatabaseURL = url
        setActivityForeground(appIsForeground)
    }

    private func invalidatePersistenceScope() {
        libraryDownloads?.invalidateSession()
        libraryDownloads=nil;libraryRepository=nil
        activityObservation?.cancel(); activityObservation = nil
        let oldActivity = activityRepository
        activityRepository = nil; conversationActivities = [:]; activitySuccessIDs = []; activitySuccessSerial = [:]; activityCursor = 0; activityNeedsSync = true
        if let oldActivity { Task { await oldActivity.invalidate() } }
        let old = conversationRepository
        primaryBotRepository?.close(); ownedTaskRepository?.close(); scheduledTaskRepository?.close()
        primaryBotRepository = nil; ownedTaskRepository = nil; scheduledTaskRepository = nil
        primaryBotID = nil; primarySettings = nil
        conversationRepository = nil
        conversationDatabaseURL = nil
        conversationDatabase?.close()
        conversationDatabase = nil
        if let old { Task { await old.invalidate() } }
    }

    /// 统一错误文案；401 时自动退出登录。网络和未知错误不用系统英文。
    func message(for error: Error) -> String {
        if let e = error as? APIError, e.status == 401 {
            signOut()
        }
        return UserFacingError.message(for: error)
    }
}

/// 界面上的错误句子。传输失败用同一句；服务端已经写好的中文保留；其余不用 localizedDescription。
enum UserFacingError {
    static let offline = "暂时连接不上"
    static let unavailable = "这次没能完成，请稍后再试。"

    static func isTransport(_ error: Error) -> Bool {
        if ConnectionIssue.classify(error) != nil { return true }
        if let api = error as? APIError, (500...599).contains(api.status) { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code != NSURLErrorCancelled
    }

    static func message(for error: Error) -> String {
        if isTransport(error) { return offline }
        if let api = error as? APIError {
            let text = api.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? unavailable : text
        }
        if let text = (error as? LocalizedError)?.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, text.contains(where: isChinese) {
            return text
        }
        return unavailable
    }

    private static func isChinese(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}


extension AppState {
    func activity(kind: String, id: Int) -> ConversationActivity? { conversationActivities["\(kind):\(id)"] }
    func setActivityForeground(_ foreground: Bool) {
        appIsForeground = foreground
        activityObservation?.cancel(); activityObservation = nil
        guard foreground, token != nil, let repository = activityRepository else { return }
        let generation = sessionGeneration
        let client = api
        activityObservation = Task { [weak self] in
            guard let self else { return }
            if let cached = try? await repository.cached(ConversationActivitySnapshot.self, key: "activity"), self.isCurrentSession(generation) {
                self.conversationActivities = Dictionary(uniqueKeysWithValues: cached.conversations.map { ($0.id, $0) })
            }
            while !Task.isCancelled && self.isCurrentSession(generation) {
                do {
                    let snapshot = try await client.conversationActivity()
                    guard !Task.isCancelled, self.isCurrentSession(generation) else { return }
                    self.conversationActivities = Dictionary(uniqueKeysWithValues: snapshot.conversations.map { ($0.id, $0) })
                    self.activityCursor = snapshot.cursor; self.activityNeedsSync = false
                    try await repository.save(snapshot, key: "activity")
                    await self.flushReadOutbox()
                    for try await event in client.conversationEvents(afterID: snapshot.cursor) {
                        guard !Task.isCancelled, self.isCurrentSession(generation) else { return }
                        let update = try JSONDecoder().decode(ConversationActivityEvent.self, from: event.data)
                        let key = "\(update.kind):\(update.conversationID)"
                        if let conversation = update.conversation {
                            let previous = self.conversationActivities[key]
                            if event.name == "message_published", conversation.displayState == "idle", previous?.displayState != "idle", !conversation.hasNewlyFailedWork(since: previous) { self.showActivitySuccess(key, session: generation) }
                            if (self.conversationActivities[key]?.revision ?? 0) <= conversation.revision { self.conversationActivities[key] = conversation }
                        } else { self.conversationActivities.removeValue(forKey: key) }
                        self.activityCursor = event.id
                        // Save summaries and cursor atomically as one Codable snapshot.
                        let data = try JSONSerialization.data(withJSONObject: ["cursor": event.id, "conversations": try self.conversationActivities.values.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }])
                        try await repository.save(JSONDecoder().decode(ConversationActivitySnapshot.self, from: data), key: "activity")
                    }
                } catch {
                    guard !Task.isCancelled, self.isCurrentSession(generation) else { return }
                    self.activityNeedsSync = true
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    private func showActivitySuccess(_ key: String, session: UInt64) {
        let serial = (activitySuccessSerial[key] ?? 0) + 1
        activitySuccessSerial[key] = serial; activitySuccessIDs.insert(key)
        Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            guard let self, self.isCurrentSession(session), self.activitySuccessSerial[key] == serial else { return }
            self.activitySuccessIDs.remove(key)
        }
    }
    func refreshActivityForEntry() async {
        let session = sessionGeneration
        guard let repository = activityRepository else { return }
        do {
            let snapshot = try await api.conversationActivity()
            guard isCurrentSession(session), !Task.isCancelled else { return }
            for row in snapshot.conversations where (conversationActivities[row.id]?.revision ?? 0) <= row.revision { conversationActivities[row.id] = row }
            try await repository.save(snapshot, key: "activity")
        } catch { activityNeedsSync = true }
    }
    func markVisible(kind: String, id: Int, generation: Int, message: MessagePublication) async {
        guard appIsForeground, let repository = activityRepository else { return }
        try? await repository.enqueueRead(kind: kind, id: id, generation: generation, message: message)
        await flushReadOutbox()
    }
    /// 打开（或正在看）对话时把该对话全部未读回复标为已读：先写本地已读队列，再上报服务端。
    func markConversationRead(kind: String, id: Int) async {
        guard appIsForeground, let repository = activityRepository, let row = activity(kind: kind, id: id) else { return }
        let batch = row.entryReadBatch
        guard !batch.isEmpty else { return }
        for message in batch { try? await repository.enqueueRead(kind: kind, id: id, generation: row.generation, message: message) }
        await flushReadOutbox()
    }
    func flushReadOutbox() async {
        guard appIsForeground, let repository = activityRepository else { return }
        let session = sessionGeneration
        for row in conversationActivities.values {
            guard isCurrentSession(session), !Task.isCancelled else { return }
            guard let messages = try? await repository.readOutbox(kind: row.kind, id: row.conversationID, generation: row.generation), !messages.isEmpty else { continue }
            do {
                let result = try await api.readConversation(kind: row.kind, id: row.conversationID, generation: row.generation, messages: messages)
                guard isCurrentSession(session) else { return }
                if (conversationActivities[row.id]?.revision ?? 0) <= result.conversation.revision { conversationActivities[row.id] = result.conversation }
                try await repository.acknowledgeReads(kind: row.kind, id: row.conversationID, generation: row.generation, messages: messages)
            } catch let error as APIError where error.code == "generation_changed" || error.code == "publication_changed" {
                // Discard only the rejected revisions, not newer entries queued during the HTTP request.
                try? await repository.acknowledgeReads(kind: row.kind, id: row.conversationID, generation: row.generation, messages: messages)
            } catch { activityNeedsSync = true }
        }
    }
}
