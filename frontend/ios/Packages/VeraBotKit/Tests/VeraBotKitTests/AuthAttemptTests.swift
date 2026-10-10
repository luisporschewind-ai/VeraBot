import Testing
@testable import VeraBotNetworking

@Test func signedOutAuthAttemptCanReceiveSuccessAndFailure() {
    let session = AuthSession(tokens: nil)
    let attempt = session.generation
    #expect(session.isCurrentAuthAttempt(attempt))
    // 未登录请求可处理结果，但读取账号数据仍必须有登录态。
    #expect(!session.isCurrent(attempt))
}

@Test func signInInvalidatesPreviousAuthAttempt() {
    let session = AuthSession(tokens: nil)
    let attempt = session.generation
    session.set(AuthTokens(access: "new-account", refresh: nil))
    #expect(!session.isCurrentAuthAttempt(attempt))
    #expect(session.isCurrent(session.generation))
}

@Test func signOutInvalidatesPreviousAuthAttemptEvenWhenAlreadySignedOut() {
    let session = AuthSession(tokens: nil)
    let attempt = session.generation
    session.set(nil)
    #expect(!session.isCurrentAuthAttempt(attempt))
    #expect(session.isCurrentAuthAttempt(session.generation))
    #expect(!session.isCurrent(session.generation))
}
