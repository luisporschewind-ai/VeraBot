// 访问令牌 + 刷新令牌的共享持有者：APIClient 遇到 401 时透明刷新一次并重试（多个并发请求只刷新一次）。
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import VeraBotCore

public struct AuthTokens: Codable, Sendable, Equatable {
    public var access: String
    public var refresh: String?

    public init(access: String, refresh: String?) {
        self.access = access
        self.refresh = refresh
    }
}

/// 刷新的结果：新令牌 / 刷新令牌已失效（需要重新登录）/ 暂时失败（网络等，保留登录态）。
public enum RefreshOutcome: Sendable, Equatable {
    case refreshed(AuthTokens)
    case rejected
    case unavailable
}

/// 线程安全的令牌容器（锁保护，同步读写），刷新用单个共享 Task 去重。
public final class AuthSession: @unchecked Sendable {
    private let lock = NSLock()
    private var current: AuthTokens?
    private var inflight: Task<RefreshOutcome, Never>?
    private let onChange: @Sendable (AuthTokens?, _ expired: Bool) -> Void

    /// onChange：令牌变化（刷新成功 / 登录 / 退出）时回调，用来写 Keychain；expired = 刷新令牌被后端拒绝。
    public init(tokens: AuthTokens?, onChange: @escaping @Sendable (AuthTokens?, _ expired: Bool) -> Void = { _, _ in }) {
        current = tokens
        self.onChange = onChange
    }

    public var tokens: AuthTokens? { lock.withLock { current } }
    public var accessToken: String? { lock.withLock { current?.access } }

    public func set(_ tokens: AuthTokens?) {
        lock.withLock { current = tokens; inflight = nil }
        onChange(tokens, false)
    }

    /// 某个请求带着 `failedAccess` 收到 401 时调用。别的请求已经刷新过就直接用新令牌。
    public func refresh(after failedAccess: String?, baseURL: URL) async -> RefreshOutcome {
        let task: Task<RefreshOutcome, Never>? = lock.withLock {
            guard let cur = current else { return nil }
            if cur.access != failedAccess {   // 已被并发请求刷新
                let fresh = cur
                return Task { .refreshed(fresh) }
            }
            if let inflight { return inflight }
            guard let refresh = cur.refresh else { return nil }
            let t = Task { await Self.performRefresh(refresh, baseURL: baseURL) }
            inflight = t
            return t
        }
        guard let task else { return .rejected }
        let outcome = await task.value
        var notify: (AuthTokens?, Bool)?
        lock.withLock {
            guard inflight == task else { return }   // set() 已经替换过令牌
            inflight = nil
            switch outcome {
            case .refreshed(let t): current = t; notify = (t, false)
            case .rejected: current = nil; notify = (nil, true)
            case .unavailable: break
            }
        }
        if let notify { onChange(notify.0, notify.1) }
        return outcome
    }

    static func performRefresh(_ refreshToken: String, baseURL: URL) async -> RefreshOutcome {
        var req = URLRequest(url: baseURL.appending(path: "/api/auth/refresh"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(RefreshRequest(refreshToken: refreshToken))
        req.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status), let auth = try? JSONDecoder().decode(AuthResponse.self, from: data) {
                return .refreshed(AuthTokens(access: auth.token, refresh: auth.refreshToken ?? refreshToken))
            }
            return (status == 401 || status == 403) ? .rejected : .unavailable
        } catch {
            return .unavailable
        }
    }
}
