import Testing
@testable import VeraBotCore

@Test func smileEyesEaseInHoldAndReturnToIdle() {
    #expect(BotAvatarSmileMotion.sample(milliseconds: 0) == 0)
    let entering = BotAvatarSmileMotion.sample(milliseconds: 300)
    #expect(entering > 0 && entering < 1)
    #expect(BotAvatarSmileMotion.sample(milliseconds: 1000) == 1)
    #expect(BotAvatarSmileMotion.sample(milliseconds: BotAvatarSmileMotion.durationMS) == 0)
}

@Test func reducedMotionKeepsSmileWithoutMovement() {
    #expect(BotAvatarSmileMotion.sample(milliseconds: 0, reduceMotion: true) == 1)
    #expect(BotAvatarSmileMotion.sample(milliseconds: 9000, reduceMotion: true) == 1)
    #expect(BotAvatarSmileMotion.sample(milliseconds: -.infinity) == 0)
    #expect(BotAvatarSmileMotion.sample(milliseconds: .nan) == 0)
}
