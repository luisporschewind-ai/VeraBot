import Foundation
import Testing
@testable import VeraBotCore
@testable import VeraBotNetworking

@Test func authResponseDecodesRefreshFields() throws {
    let json = ##"{"token":"a","refresh_token":"r","expires_in":604800,"refresh_expires_in":5184000,"user":{"id":3,"username":"u_ab12","display_name":"luis","email":"luis@example.com","email_verified":false,"phone":null}}"##
    let r = try JSONDecoder().decode(AuthResponse.self, from: Data(json.utf8))
    #expect(r.token == "a" && r.refreshToken == "r" && r.expiresIn == 604800)
    #expect(r.user.email == "luis@example.com")
    #expect(r.user.needsEmailVerification)
    #expect(r.user.accountLabel == "luis@example.com")
}

@Test func legacyAuthResponseStillDecodes() throws {
    let json = ##"{"token":"a","user":{"id":1,"username":"demo"}}"##
    let r = try JSONDecoder().decode(AuthResponse.self, from: Data(json.utf8))
    #expect(r.refreshToken == nil)
    #expect(r.user.email == nil && r.user.phone == nil && !r.user.emailVerified)
    #expect(r.user.accountLabel == "用户名 demo")
    #expect(!r.user.needsEmailVerification)
}

@Test func phoneAccountLabel() throws {
    let json = ##"{"id":2,"username":"u_x","phone":"+8613800138000"}"##
    let u = try JSONDecoder().decode(User.self, from: Data(json.utf8))
    #expect(u.accountLabel == "+86 138 0013 8000")
}

@Test func userRoundTripKeepsAccountFields() throws {
    let u = User(id: 1, username: "u", email: "a@b.co", emailVerified: true, phone: nil)
    let back = try JSONDecoder().decode(User.self, from: JSONEncoder().encode(u))
    #expect(back.email == "a@b.co" && back.emailVerified)
}

@Test func registerRequestOmitsMissingChannel() throws {
    let data = try JSONEncoder().encode(RegisterRequest(phone: "+8613800138000", password: "pw123456"))
    let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(Set(obj.keys) == ["phone", "password"])
    let refresh = try JSONSerialization.jsonObject(with: JSONEncoder().encode(RefreshRequest(refreshToken: "x"))) as! [String: Any]
    #expect(refresh["refresh_token"] as? String == "x")
}

@Test func inputRulesMatchBackend() {
    #expect(AuthInputRules.normalizedEmail("  Luis@Example.COM ") == "luis@example.com")
    #expect(AuthInputRules.normalizedEmail("demo") == nil)
    #expect(AuthInputRules.normalizedEmail("a@b") == nil)
    #expect(AuthInputRules.normalizedPhone("138 0013 8000") == "+8613800138000")
    #expect(AuthInputRules.normalizedPhone("008613800138000") == "+8613800138000")
    #expect(AuthInputRules.normalizedPhone("+1 (415) 555-0123") == "+14155550123")
    #expect(AuthInputRules.normalizedPhone("12345") == nil)
    #expect(AuthInputRules.isValidCode("012345") && !AuthInputRules.isValidCode("12a456"))
    #expect(AuthMethod.allCases.map(\.title) == ["邮箱", "验证码", "手机号"])
    #expect(!AuthMethod.emailCode.supportsRegister)
}

@Test func sessionReusesTokenRefreshedByAnotherRequest() async {
    let changes = ChangeLog()
    let session = AuthSession(tokens: AuthTokens(access: "new", refresh: "r2")) { t, expired in changes.add(t?.access, expired) }
    // 请求带着旧令牌 "old" 失败，但 session 里已经是 "new"：不走网络，直接复用
    let outcome = await session.refresh(after: "old", baseURL: URL(string: "http://127.0.0.1:9")!)
    #expect(outcome == .refreshed(AuthTokens(access: "new", refresh: "r2")))
}

@Test func sessionWithoutRefreshTokenIsRejected() async {
    let session = AuthSession(tokens: AuthTokens(access: "a", refresh: nil))
    let outcome = await session.refresh(after: "a", baseURL: URL(string: "http://127.0.0.1:9")!)
    #expect(outcome == .rejected)
}

@Test func sessionNetworkFailureKeepsTokens() async {
    let changes = ChangeLog()
    let session = AuthSession(tokens: AuthTokens(access: "a", refresh: "r")) { t, expired in changes.add(t?.access, expired) }
    let outcome = await session.refresh(after: "a", baseURL: URL(string: "http://127.0.0.1:9")!)
    #expect(outcome == .unavailable)
    #expect(session.accessToken == "a")
    #expect(changes.items.isEmpty)
    session.set(nil)
    #expect(session.accessToken == nil && changes.items.count == 1)
}

@Test func clientPrefersSessionToken() {
    let session = AuthSession(tokens: AuthTokens(access: "s", refresh: nil))
    let c = APIClient(baseURL: URL(string: "http://x")!, session: session)
    #expect(c.token == "s")
    session.set(AuthTokens(access: "t", refresh: "r"))
    #expect(c.token == "t")
    #expect(APIClient(baseURL: URL(string: "http://x")!, token: "fixed").token == "fixed")
}

final class ChangeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [(String?, Bool)] = []
    func add(_ a: String?, _ e: Bool) { lock.withLock { store.append((a, e)) } }
    var items: [(String?, Bool)] { lock.withLock { store } }
}
