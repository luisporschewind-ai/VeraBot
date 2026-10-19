import Foundation
import Testing
@testable import VeraBotTTS

private final class SessionDriver: AudioSessionDriver, @unchecked Sendable {
    enum Failure: Error { case injected }
    var calls: [String] = []
    var failActivation = false
    var failRelease = false
    func activate(owner: AudioOwner) throws {
        calls.append("activate:\(owner)")
        if failActivation { throw Failure.injected }
    }
    func deactivate() throws {
        calls.append("deactivate")
        if failRelease { throw Failure.injected }
    }
}

@MainActor @Suite struct AudioSessionCoordinatorTests {
    @Test func revocationCannotReenterAndOverwriteSuccessor() throws {
        let driver = SessionDriver()
        let subject = AudioSessionCoordinator(driver: driver)
        var nested: AudioLease?
        _ = try subject.acquire(owner: .game) {
            nested = try? subject.acquire(owner: .recording) {}
        }
        let speech = try #require(subject.acquire(owner: .tts) {})
        #expect(nested == nil)
        #expect(subject.owns(speech))
        #expect(driver.calls == ["activate:game", "activate:tts"])
    }
    @Test func actualSpeechAdapterReleasesOnlyItsLease() throws {
        let driver = SessionDriver()
        let subject = AudioSessionCoordinator(driver: driver)
        let speech = SystemSpeechAudioSession(coordinator: subject)
        var stopped = false
        speech.onRevoked = { stopped = true }
        try speech.activate()
        let recording = try #require(subject.acquire(owner: .recording) {})
        #expect(stopped)
        try speech.deactivate()
        #expect(subject.owns(recording))
        #expect(driver.calls == ["activate:tts", "activate:recording"])
        #expect(throws: (any Error).self) { try speech.activate() }
        try subject.release(recording)
        try speech.activate()
        try speech.deactivate()
        #expect(driver.calls.suffix(2) == ["activate:tts", "deactivate"])
    }
    @Test func higherPriorityStopsBeforeConfiguringAndOldReleaseIsHarmless() throws {
        let driver = SessionDriver(), coordinator = AudioSessionCoordinator(driver: SessionDriver())
        let subject = AudioSessionCoordinator(driver: driver)
        let game = try #require(subject.acquire(owner: .game) { driver.calls.append("stop:game") })
        let speech = try #require(subject.acquire(owner: .tts) { driver.calls.append("stop:tts") })
        let recording = try #require(subject.acquire(owner: .recording) {})
        try subject.release(game)
        try subject.release(speech)
        #expect(driver.calls == ["activate:game", "stop:game", "activate:tts", "stop:tts", "activate:recording"])
        #expect(subject.owns(recording))
        #expect(!coordinator.owns(recording))
    }
    @Test func lowerAndEqualOwnersCannotActivate() throws {
        let driver = SessionDriver(), subject = AudioSessionCoordinator(driver: SessionDriver())
        let other = AudioSessionCoordinator(driver: driver)
        let recording = try #require(other.acquire(owner: .recording) {})
        let game = try other.acquire(owner: .game) {}
        let equal = try other.acquire(owner: .recording) {}
        #expect(game == nil && equal == nil)
        #expect(driver.calls == ["activate:recording"])
        #expect(other.owns(recording) && !subject.owns(recording))
    }
    @Test func releaseIsIdempotent() throws {
        let driver = SessionDriver(), subject = AudioSessionCoordinator(driver: SessionDriver())
        let other = AudioSessionCoordinator(driver: driver)
        let game = try #require(other.acquire(owner: .game) {})
        try subject.release(game)
        try other.release(game)
        try other.release(game)
        #expect(driver.calls == ["activate:game", "deactivate"])
    }
    @Test func failedActivationNeverRestoresRevokedOwner() throws {
        let driver = SessionDriver(), subject = AudioSessionCoordinator(driver: SessionDriver())
        let other = AudioSessionCoordinator(driver: driver)
        let game = try #require(other.acquire(owner: .game) {})
        driver.failActivation = true
        #expect(throws: SessionDriver.Failure.self) { try other.acquire(owner: .tts) {} }
        #expect(!other.owns(game) && !subject.owns(game))
        driver.failActivation = false
        let new = try #require(other.acquire(owner: .recording) {})
        try other.release(game)
        #expect(other.owns(new))
        #expect(driver.calls.last == "activate:recording")
    }
    @Test func releaseFailureCanRetryButCannotCloseNewOwner() throws {
        let driver = SessionDriver()
        let subject = AudioSessionCoordinator(driver: driver)
        let old = try #require(subject.acquire(owner: .game) {})
        driver.failRelease = true
        #expect(throws: SessionDriver.Failure.self) { try subject.release(old) }
        driver.failRelease = false
        let recording = try #require(subject.acquire(owner: .recording) {})
        let calls = driver.calls
        try subject.release(old)
        #expect(driver.calls == calls && subject.owns(recording))
        try subject.release(recording)
        #expect(driver.calls.last == "deactivate")
    }
    @Test func revocationCanReleaseItselfSynchronously() throws {
        let driver = SessionDriver()
        let subject = AudioSessionCoordinator(driver: driver)
        // Driver callback exercises recursive cleanup without a stale global deactivate.
        let game = try #require(subject.acquire(owner: .game) {})
        try subject.release(game)
        let next = try #require(subject.acquire(owner: .tts) { try? subject.release(game) })
        _ = try subject.acquire(owner: .recording) {}
        #expect(!subject.owns(next))
        #expect(driver.calls == ["activate:game", "deactivate", "activate:tts", "activate:recording"])
    }
}
