import Testing
@testable import VeraBotCore

@Test func tetrisCompanionLimitsAndQuietMode() {
    var policy = TetrisCompanionPolicy()
    let reserved7 = policy.reserve(at: 0)
    #expect(reserved7)
    let reserved6 = policy.reserve(at: 29)
    #expect(!reserved6)
    let reserved5 = policy.reserve(at: 30)
    #expect(reserved5)
    let reserved4 = policy.reserve(at: 60)
    #expect(reserved4)
    let reserved3 = policy.reserve(at: 120)
    #expect(!reserved3)
    policy = TetrisCompanionPolicy()
    policy.isQuiet = true
    let reserved2 = policy.reserve(at: 0)
    #expect(!reserved2)
    policy.isQuiet = false
    let reserved1 = policy.reserve(at: 0)
    #expect(reserved1)
}
