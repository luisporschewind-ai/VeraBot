import Foundation
import Testing
@testable import VeraBotNetworking

// These catch transport failures being presented as bad credentials or every HTTP error as an outage.
@Test func connectionIssueRecognizesOfflineAndDroppedNetwork() {
    #expect(ConnectionIssue.classify(URLError(.notConnectedToInternet)) == .offline)
    #expect(ConnectionIssue.classify(URLError(.networkConnectionLost)) == .offline)
    #expect(ConnectionIssue.classify(URLError(.dataNotAllowed)) == .offline)
    #expect(ConnectionIssue.classify(URLError(.internationalRoamingOff)) == .offline)
}

@Test func connectionIssueDistinguishesTimeoutFromUnreachableServer() {
    #expect(ConnectionIssue.classify(URLError(.timedOut)) == .timedOut)
    #expect(ConnectionIssue.classify(URLError(.cannotConnectToHost)) == .unreachable)
    #expect(ConnectionIssue.classify(URLError(.cannotFindHost)) == .unreachable)
    #expect(ConnectionIssue.classify(URLError(.dnsLookupFailed)) == .unreachable)
}

@Test func connectionIssueRecognizesServerOutageWithoutMisclassifyingAccountErrors() {
    #expect(ConnectionIssue.classify(APIError(status: 503, message: "internal detail")) == .serviceUnavailable)
    #expect(ConnectionIssue.classify(APIError(status: 401, message: "bad credentials")) == nil)
    #expect(ConnectionIssue.classify(APIError(status: 422, message: "bad email")) == nil)
    #expect(ConnectionIssue.classify(APIError(status: 429, message: "rate limited")) == nil)
}

@Test func connectionIssueIgnoresCancellationAndMalformedResponses() {
    #expect(ConnectionIssue.classify(CancellationError()) == nil)
    #expect(ConnectionIssue.classify(URLError(.cancelled)) == nil)
    #expect(ConnectionIssue.classify(URLError(.badServerResponse)) == nil)
}

@Test func connectionIssueHandlesNSErrorFromSystemTransport() {
    #expect(ConnectionIssue.classify(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)) == .timedOut)
    #expect(ConnectionIssue.classify(NSError(domain: "custom", code: NSURLErrorTimedOut)) == nil)
}
