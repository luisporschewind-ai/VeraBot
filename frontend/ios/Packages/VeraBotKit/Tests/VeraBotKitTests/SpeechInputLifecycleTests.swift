import Foundation
import Testing
@testable import VeraBotCore

private func waitForSignal(_ value: DispatchSemaphore) { value.wait() }
private func waitBriefly(_ value: DispatchSemaphore) -> DispatchTimeoutResult { value.wait(timeout: .now() + .milliseconds(50)) }

@Suite struct SpeechInputLifecycleTests {
    @Test func staleCallbackCannotTearDownNewInput() {
        let lifecycle = SpeechInputLifecycle()
        let first = lifecycle.begin { $0 }
        lifecycle.invalidate {}
        let second = lifecycle.begin { $0 }
        var stopped = false
        let oldResult = lifecycle.withCurrent(first) { stopped = true }
        #expect(oldResult == nil && !stopped)
        let currentResult = lifecycle.withCurrent(second) { stopped = true }
        #expect(currentResult != nil && stopped)
    }
    @Test func callbackAndNewStartAreSerialized() async {
        let lifecycle = SpeechInputLifecycle()
        let first = lifecycle.begin { $0 }
        let callbackEntered = DispatchSemaphore(value: 0)
        let releaseCallback = DispatchSemaphore(value: 0)
        let startAttempted = DispatchSemaphore(value: 0)
        let newStartEntered = DispatchSemaphore(value: 0)
        let old = Task.detached {
            lifecycle.withCurrent(first) {
                callbackEntered.signal()
                releaseCallback.wait()
            }
        }
        await Task.detached { waitForSignal(callbackEntered) }.value
        let next = Task.detached {
            startAttempted.signal()
            return lifecycle.begin { generation in newStartEntered.signal(); return generation }
        }
        await Task.detached { waitForSignal(startAttempted) }.value
        let blocked = await Task.detached { waitBriefly(newStartEntered) }.value
        #expect(blocked == .timedOut)
        // Releasing the callback permits the waiting transition; its returned epoch
        // must be newer and the old callback must then be unable to touch resources.
        releaseCallback.signal()
        _ = await old.value
        let second = await next.value
        #expect(second != first)
        let stale = lifecycle.withCurrent(first) { false }
        #expect(stale == nil)
    }
}
